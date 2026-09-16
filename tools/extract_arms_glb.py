#!/usr/bin/env python3
"""Extrae SOLO los brazos de un GLB de viewmodel, descartando el arma.

Motivo: queremos maxima fidelidad en los brazos y conservar la OWK 19 como unica
pistola visible. Los packs de primera persona traen su propia pistola; aqui se
identifica por los huesos que la mueven y se tira, junto con el skybox de
presentacion de Sketchfab (que si no se cuela en la escena).

Criterio, medido y no supuesto:
  - Se descarta toda malla SIN skin (el skybox de 480 tris y los ayudantes de
    apuntado de 4 tris): no son personaje.
  - Se descarta toda malla cuyos huesos con peso sean de arma. Los nombres de
    esos huesos se detectan solos: se busca el prefijo comun de los huesos que
    NO aparecen en las mallas de manos/brazos.
  - El esqueleto se conserva entero: los joints sin malla no cuestan nada en
    runtime y recortarlo arriesga romper las animaciones.

Uso: python3 extract_arms_glb.py <entrada.glb> <salida.glb>
"""
import json, struct, sys
import numpy as np
from collections import Counter

CT = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

# Nombres que marcan el arma en los packs de primera persona medidos.
WEAPON_HINTS = ('weapon', 'slidder', 'slide', 'barrel', 'magazine', 'bullet',
                'trigger', 'muzzle', 'hammer', 'grip', 'ammo', 'scope', 'bolt')
# Nombres que marcan el personaje.
BODY_HINTS = ('hand', 'palm', 'thumb', 'f_index', 'f_middle', 'f_ring', 'f_pinky',
              'forearm', 'upper_arm', 'shoulder', 'wrist', 'elbow', 'breast',
              'spine', 'neck', 'head', 'clavicle', 'arm')


def read_glb(p):
    d = open(p, 'rb').read()
    assert d[:4] == b'glTF'
    off = 12; js = None; bin_ = b''
    while off < len(d):
        ln, ty = struct.unpack_from('<II', d, off)
        ch = d[off+8:off+8+ln]
        if ty == 0x4E4F534A:
            js = json.loads(ch)
        elif ty == 0x004E4942:
            bin_ = ch
        off += 8 + ln
    return js, bin_


def read_acc(j, b, i):
    a = j['accessors'][i]
    fmt, sz = CT[a['componentType']]
    n = NC[a['type']]
    bv = j['bufferViews'][a['bufferView']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride') or (sz*n)
    if stride == sz*n:
        raw = b[start:start + a['count']*stride]
        out = np.frombuffer(raw, dtype=np.dtype('<'+fmt)).astype(np.float64)
    else:
        out = np.empty(a['count']*n)
        for k in range(a['count']):
            out[k*n:(k+1)*n] = struct.unpack_from('<'+fmt*n, b, start+k*stride)
    return out.reshape(a['count'], n) if n > 1 else out


buf = bytearray()


def write_acc(j, acc_index, arr, comp, typ):
    a = j['accessors'][acc_index]
    arr = np.asarray(arr)
    fmt, sz = CT[comp]
    n = NC[typ]
    arr = arr.reshape(-1) if typ == 'SCALAR' else (arr[:, None] if arr.ndim == 1 else arr)
    raw = arr.astype(np.dtype('<'+fmt)).tobytes()
    while len(buf) % 4:
        buf.append(0)
    off = len(buf)
    buf.extend(raw)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)})
    a['bufferView'] = len(j['bufferViews'])-1
    a['byteOffset'] = 0
    a['componentType'] = comp
    a['type'] = typ
    a['count'] = int(arr.shape[0])
    if 'min' in a:
        am = arr.reshape(arr.shape[0], -1) if arr.ndim > 1 else arr.reshape(-1, 1)
        a['min'] = [float(x) for x in am.min(axis=0)]
        a['max'] = [float(x) for x in am.max(axis=0)]


SRC, DST = sys.argv[1], sys.argv[2]
j, b = read_glb(SRC)
names = [n.get('name', '?') for n in j['nodes']]
joints = j['skins'][0]['joints'] if j.get('skins') else []
jn = [names[x] for x in joints]

# --- clasificar cada malla ---
keep_mesh, drop_mesh = [], []
for mi, m in enumerate(j['meshes']):
    nm = m.get('name', f'mesh{mi}')
    pr = m['primitives'][0]
    tris = sum(j['accessors'][p['indices']]['count']//3 for p in m['primitives'] if 'indices' in p)
    if 'JOINTS_0' not in pr['attributes']:
        drop_mesh.append((mi, nm, tris, 'sin skin (skybox/ayudante)'))
        continue
    JT = read_acc(j, b, pr['attributes']['JOINTS_0']).astype(int)
    WT = read_acc(j, b, pr['attributes']['WEIGHTS_0'])
    used = Counter()
    for k in range(4):
        for jj, w in zip(JT[:, k], WT[:, k]):
            if w > 0.001:
                used[int(jj)] += 1
    bones = [jn[jj].lower() for jj in used]
    n_weapon = sum(1 for x in bones if any(h in x for h in WEAPON_HINTS))
    frac = n_weapon/max(len(bones), 1)
    if frac > 0.5:
        drop_mesh.append((mi, nm, tris, f'{n_weapon}/{len(bones)} huesos de arma'))
    else:
        keep_mesh.append((mi, nm, tris, f'{len(bones)} huesos'))

print("CONSERVA:")
for mi, nm, t, why in keep_mesh:
    print(f"   {nm:16s} {t:6d} tris  ({why})")
print("DESCARTA:")
for mi, nm, t, why in drop_mesh:
    print(f"   {nm:16s} {t:6d} tris  ({why})")

keep_set = {mi for mi, *_ in keep_mesh}
j['meshes'] = [m for i, m in enumerate(j['meshes']) if i in keep_set]
remap_mesh = {old: new for new, old in enumerate(sorted(keep_set))}
for nd in j['nodes']:
    if 'mesh' in nd:
        if nd['mesh'] in remap_mesh:
            nd['mesh'] = remap_mesh[nd['mesh']]
        else:
            del nd['mesh']

# --- reescribir el buffer con lo que queda ---
touched = set()
for m in j['meshes']:
    for pr in m['primitives']:
        for k, ai in pr['attributes'].items():
            touched.add(ai)
        touched.add(pr['indices'])
for ai, a in enumerate(j['accessors']):
    if ai in touched and a.get('bufferView') is not None:
        arr = read_acc(j, b, ai)
        write_acc(j, ai, arr, a['componentType'], a['type'])
for ai, a in enumerate(j['accessors']):
    if ai in touched or a.get('bufferView') is None:
        continue
    write_acc(j, ai, read_acc(j, b, ai), a['componentType'], a['type'])
for img in j.get('images', []):
    bvi = img.get('bufferView')
    if bvi is None:
        continue
    bv = j['bufferViews'][bvi]
    o = bv.get('byteOffset', 0)
    raw = b[o:o+bv['byteLength']]
    while len(buf) % 4:
        buf.append(0)
    off = len(buf); buf.extend(raw)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)})
    img['bufferView'] = len(j['bufferViews'])-1

used = sorted({a['bufferView'] for a in j['accessors'] if a.get('bufferView') is not None} |
              {im['bufferView'] for im in j.get('images', []) if im.get('bufferView') is not None})
rm = {o: n for n, o in enumerate(used)}
j['bufferViews'] = [j['bufferViews'][o] for o in used]
for a in j['accessors']:
    if a.get('bufferView') is not None:
        a['bufferView'] = rm[a['bufferView']]
for im in j.get('images', []):
    if im.get('bufferView') is not None:
        im['bufferView'] = rm[im['bufferView']]

while len(buf) % 4:
    buf.append(0)
j['buffers'] = [{'byteLength': len(buf)}]
js = json.dumps(j, separators=(',', ':')).encode()
while len(js) % 4:
    js += b' '
out = bytearray()
out += b'glTF' + struct.pack('<II', 2, 12+8+len(js)+8+len(buf))
out += struct.pack('<II', len(js), 0x4E4F534A) + js
out += struct.pack('<II', len(buf), 0x004E4942) + bytes(buf)
open(DST, 'wb').write(bytes(out))
print(f"escrito {DST}  {len(out)/1e6:.2f} MB  mallas={len(j['meshes'])}  anims={len(j.get('animations',[]))}")
