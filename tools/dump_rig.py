#!/usr/bin/env python3
"""Extrae el esqueleto (nombres, jerarquia, reposo) y las animaciones de un GLB a JSON,
para poder mapear huesos entre dos rigs sin depender del motor.

Uso: python3 dump_rig.py <glb> <salida.json>
"""
import json, struct, sys
import numpy as np

CT = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_glb(p):
    d = open(p, 'rb').read(); off = 12; js = None; b = b''
    while off < len(d):
        ln, ty = struct.unpack_from('<II', d, off)
        ch = d[off+8:off+8+ln]
        if ty == 0x4E4F534A:
            js = json.loads(ch)
        elif ty == 0x004E4942:
            b = ch
        off += 8 + ln
    return js, b


def mk(j, b):
    def acc(i):
        a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
        fmt, sz = CT[a['componentType']]; n = NC[a['type']]
        st = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride') or (sz*n)
        if stride == sz*n:
            o = np.frombuffer(b[st:st+a['count']*stride], dtype=np.dtype('<'+fmt)).astype(np.float64)
        else:
            o = np.empty(a['count']*n)
            for k in range(a['count']):
                o[k*n:(k+1)*n] = struct.unpack_from('<'+fmt*n, b, st+k*stride)
        return o.reshape(a['count'], n) if n > 1 else o
    return acc


SRC, OUT = sys.argv[1], sys.argv[2]
j, b = read_glb(SRC)
acc = mk(j, b)
names = [n.get('name', f'node{i}') for i, n in enumerate(j['nodes'])]
parents = {}
for ni, nd in enumerate(j['nodes']):
    for c in nd.get('children', []):
        parents[c] = ni

skin = j['skins'][0]
joints = skin['joints']
jid = {n: k for k, n in enumerate(joints)}


def qmat(q):
    x, y, z, w = q
    n = x*x+y*y+z*z+w*w
    if n < 1e-12:
        return np.eye(3)
    s = 2.0/n
    return np.array([[1-s*(y*y+z*z), s*(x*y-z*w), s*(x*z+y*w)],
                     [s*(x*y+z*w), 1-s*(x*x+z*z), s*(y*z-x*w)],
                     [s*(x*z-y*w), s*(y*z+x*w), 1-s*(x*x+y*y)]])


# reposo por nodo (TRS del propio nodo, sin animacion)
def local_rest(ni):
    nd = j['nodes'][ni]
    L = np.eye(4)
    L[:3, :3] = qmat(nd.get('rotation', [0, 0, 0, 1])) @ np.diag(nd.get('scale', [1, 1, 1]))
    L[:3, 3] = nd.get('translation', [0, 0, 0])
    return L


W = {}
def world(ni):
    if ni in W:
        return W[ni]
    p = parents.get(ni)
    W[ni] = (world(p) @ local_rest(ni)) if p is not None else local_rest(ni)
    return W[ni]
for ni in range(len(j['nodes'])):
    world(ni)

bones = []
for k, ni in enumerate(joints):
    p = parents.get(ni)
    bones.append({
        'name': names[ni],
        'parent': names[p] if p is not None else None,
        'head': [float(x) for x in world(ni)[:3, 3]],
        'rest_local_translation': [float(x) for x in j['nodes'][ni].get('translation', [0, 0, 0])],
        'rest_local_rotation': [float(x) for x in j['nodes'][ni].get('rotation', [0, 0, 0, 1])],
        'rest_local_scale': [float(x) for x in j['nodes'][ni].get('scale', [1, 1, 1])],
    })

# --- animaciones: muestrear rotaciones locales por hueso ---
def sample(sampler, t):
    inp = acc(sampler['input']); outp = acc(sampler['output'])
    if len(inp) == 1:
        return outp[0]
    i = max(0, min(int(np.searchsorted(inp, t, side='right')-1), len(inp)-2))
    f = 0.0 if inp[i+1] == inp[i] else (t-inp[i])/(inp[i+1]-inp[i])
    return outp[i]*(1-f) + outp[i+1]*f


anims = {}
for a in j.get('animations', []):
    an = a.get('name')
    # duracion
    dur = 0.0
    for s in a['samplers']:
        t = acc(s['input'])
        dur = max(dur, float(t.max()))
    tracks = {}
    for ch in a['channels']:
        ni = ch['target']['node']
        path = ch['target']['path']
        if path != 'rotation' or ni not in jid:
            continue
        bn = names[ni]
        inp = acc(a['samplers'][ch['sampler']]['input'])
        times = [float(x) for x in inp]
        quats = []
        for t in times:
            v = sample(a['samplers'][ch['sampler']], t)
            quats.append([float(x) for x in v])
        tracks[bn] = {'times': times, 'rot': quats}
    anims[an] = {'duration': dur, 'tracks': tracks}

out = {'bones': bones, 'animations': anims,
       'counts': {'joints': len(joints), 'nodes': len(j['nodes']), 'anims': len(anims)}}
json.dump(out, open(OUT, 'w'))
print(f"{OUT}: {len(bones)} huesos, {len(anims)} animaciones")
for an, d in anims.items():
    print(f"   {an}: {d['duration']:.3f}s  {len(d['tracks'])} pistas de rotacion")
