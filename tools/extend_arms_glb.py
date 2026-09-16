#!/usr/bin/env python3
"""Extiende hacia fuera los anillos de corte del antebrazo (loft), editando el GLB
directamente. NO usa Blender: el round-trip de Blender 4.0 sobre este asset
pierde el skinning (medido: silueta a 0,0% y 6 071 verts detras de la camara),
asi que el buffer se toca a mano y los 81 huesos, las 5 animaciones, los 4 mapas
y la metadata de licencia salen intactos por construccion.

QUE ARREGLA Y POR QUE ASI

Medido en espacio de camara (ojo a 0,54 m del alza, pose Idle): las manos estan a
0,58-0,66 m, pero la manga del antebrazo solo llega a 0,245-0,35 m y su anillo de
corte mira al objetivo a 0,31-0,33 m. Es lo mas cercano a la camara en pantalla,
por eso se proyecta enorme y se le ve el corte.

Dos intentos anteriores fallaron y estan documentados: tapar el anillo con un
abanico sale como tapa plana gris, y hundir/reducir el anillo arruga el cuero
(esos vertices son piel visible). La diferencia aqui es que se EXTIENDE hacia
fuera con anillos sucesivos que decrecen: la superficie nueva es un cono suave,
el corte acaba a ~0,5 m de la camara (ya lejos) y mucho mas pequeno, y los
vertices originales NO se mueven, asi que no hay arruga.

El eje de extension es la direccion del brazo alejandose de la mano, que se
obtiene del propio hueso dominante del anillo: asi el cono sigue la manga real y
no una direccion inventada.

Uso: python3 extend_arms_glb.py <entrada.glb> <salida.glb> [min_verts_anillo]
"""
import json, struct, sys
import numpy as np
from collections import defaultdict

CT = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

# Anillos del loft: (desplazamiento a lo largo del brazo en metros, factor de radio)
# El deploy del viewmodel multiplica por 0.6694, asi que 0.22 m de malla son
# ~0.147 m en pantalla. Tres anillos dan un cono suave sin gastar geometria.
RINGS = [(0.075, 0.82), (0.150, 0.58), (0.220, 0.30)]
MIN_LOOP = int(sys.argv[3]) if len(sys.argv) > 3 else 90
# Cuantos anillos de triangulos crecer hacia dentro para estimar la direccion
# del tubo. 4 pasos ~ unos cm, suficiente para promediar sin salirse del brazo.
INNER_STEPS = 4


def read_glb(p):
    d = open(p, 'rb').read()
    assert d[:4] == b'glTF', 'no es GLB'
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


def write_acc(j, acc_index, arr, comp=None, typ=None):
    a = j['accessors'][acc_index]
    arr = np.asarray(arr)
    comp = comp or a['componentType']
    typ = typ or a['type']
    fmt, sz = CT[comp]
    n = NC[typ]
    if typ == 'SCALAR':
        arr = arr.reshape(-1)
    elif arr.ndim == 1:
        arr = arr[:, None]
    assert arr.shape[-1] == n or n == 1, (arr.shape, typ)
    raw = arr.astype(np.dtype('<'+fmt)).tobytes()
    while len(buf) % 4:
        buf.append(0)
    off = len(buf)
    buf.extend(raw)
    bvi = len(j['bufferViews'])
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)})
    a['bufferView'] = bvi
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
mesh_i = [i for i, m in enumerate(j['meshes']) if m.get('name', '').startswith('arms')][0]
pr = j['meshes'][mesh_i]['primitives'][0]
attrs = pr['attributes']
print(f"malla {j['meshes'][mesh_i].get('name')}  attrs={sorted(attrs)}")

POS = read_acc(j, b, attrs['POSITION'])
JT = read_acc(j, b, attrs['JOINTS_0'])
WT = read_acc(j, b, attrs['WEIGHTS_0'])
IDX = np.asarray(read_acc(j, b, pr['indices'])).reshape(-1, 3).astype(np.int64)
UV = read_acc(j, b, attrs['TEXCOORD_0']) if 'TEXCOORD_0' in attrs else None
NRM = read_acc(j, b, attrs['NORMAL']) if 'NORMAL' in attrs else None
TAN = read_acc(j, b, attrs['TANGENT']) if 'TANGENT' in attrs else None
print(f"verts={len(POS)} tris={len(IDX)}")
tris_of = np.vstack([IDX[:, [0, 1]], IDX[:, [1, 2]], IDX[:, [2, 0]]]).astype(np.int64)

# --- anillos de frontera ---
cnt = defaultdict(int)
for t in IDX:
    for a_, b_ in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
        cnt[(min(a_, b_), max(a_, b_))] += 1
bnd = [e for e, c in cnt.items() if c == 1]
adj = defaultdict(list)
for a_, b_ in bnd:
    adj[a_].append(b_); adj[b_].append(a_)
seen = set(); loops = []
for s in list(adj):
    if s in seen:
        continue
    stack = [s]; comp = []
    while stack:
        u = stack.pop()
        if u in seen:
            continue
        seen.add(u); comp.append(u)
        for v in adj[u]:
            if v not in seen:
                stack.append(v)
    loops.append(comp)
loops.sort(key=len, reverse=True)
print(f"bucles de frontera: {len(loops)} tamanos={[len(l) for l in loops[:8]]}")

# --- ordenar cada anillo como ciclo ---
def ring_order(loop):
    s = loop[0]; order = [s]; prev = None; cur = s
    while True:
        nxt = [n for n in adj[cur] if n is not prev]
        if not nxt:
            break
        n = nxt[0]
        if n == order[0]:
            break
        order.append(n); prev, cur = cur, n
        if len(order) > len(loop)+2:
            break
    return order


# --- centroide de las manos para orientar el eje del brazo ---
names = [nd.get('name', '') for nd in j['nodes']]
jn = [names[j['skins'][0]['joints'][k]] for k in range(len(j['skins'][0]['joints']))]
# huesos de manos/dedos -> mascara por INDICE de hueso
hand_joint = np.array([any(t in n for t in ('Bone_L.', 'Bone_R.', 'Hand_L', 'Hand_R')) for n in jn])
dom = JT[np.arange(len(POS)), np.argmax(WT, axis=1)].astype(int)
sel = hand_joint[dom]
HAND_C = POS[sel].mean(axis=0) if sel.any() else POS.mean(axis=0)
print(f"centroide manos = {np.round(HAND_C,4)}")

new_pos = []; new_jt = []; new_wt = []; new_nrm = []; new_uv = []; new_tan = []
new_idx = []
extended = 0
for l in loops:
    if len(l) < MIN_LOOP:
        continue
    order = ring_order(l)
    if len(order) < 4:
        continue
    vs = np.array(order)
    c0 = POS[vs].mean(axis=0)
    # Eje de extension = direccion de la PROPIA superficie: del anillo hacia el
    # interior de la malla. Derivarlo del hueso no sirve aqui porque el brazo
    # esta doblado (medido: BoneTwist_01.L_07 head z=0.134 contra el codo en
    # z=-0.037), asi que "hacia el padre" no es "hacia dentro del antebrazo".
    # Creciendo por la conectividad se obtiene la direccion real del tubo.
    inner = set(int(v) for v in vs)
    front = set(inner)
    for _ in range(INNER_STEPS):
        nxt = set()
        for (a_, b_) in tris_of:
            if a_ in front and b_ not in inner:
                nxt.add(b_)
            elif b_ in front and a_ not in inner:
                nxt.add(a_)
        if not nxt:
            break
        inner |= nxt
        front = nxt
    inner_only = np.array(sorted(inner - set(int(v) for v in vs)))
    if inner_only.size:
        ci = POS[inner_only].mean(axis=0)
        axis = ci - c0
    else:
        axis = np.zeros(3)
    na = np.linalg.norm(axis)
    axis = axis/na if na > 1e-6 else np.array([0.0, 0.0, -1.0])
    # base de pesos: media del anillo (se replica en todos los anillos nuevos)
    wsum = defaultdict(float)
    for k in range(4):
        for v in vs:
            if WT[v, k] > 0:
                wsum[int(JT[v, k])] += float(WT[v, k])
    top = sorted(wsum.items(), key=lambda kv: -kv[1])[:4]
    tot = sum(w for _, w in top) or 1.0
    cj = [0, 0, 0, 0]; cw = [0.0, 0.0, 0.0, 0.0]
    for k, (bone, w) in enumerate(top):
        cj[k] = bone; cw[k] = w/tot

    prev_ring = vs
    first_new = len(POS) + len(new_pos)
    for (dist, scale) in RINGS:
        pts = c0 + (POS[vs]-c0)*scale + axis*dist
        base = len(POS) + len(new_pos)
        for i in range(len(vs)):
            new_pos.append(pts[i])
            new_jt.append(cj)
            new_wt.append(cw)
            if NRM is not None:
                nv = NRM[vs[i]]*0.6 + axis*0.8
                nn = np.linalg.norm(nv)
                new_nrm.append(nv/nn if nn > 1e-6 else axis)
            if UV is not None:
                new_uv.append(UV[vs[i]])
            if TAN is not None:
                new_tan.append(TAN[vs[i]])
        # puentear el anillo anterior con este
        n = len(vs)
        for i in range(n):
            a0 = prev_ring[i]; a1 = prev_ring[(i+1) % n]
            b0 = base + i; b1 = base + (i+1) % n
            new_idx.append([a0, b0, b1])
            new_idx.append([a0, b1, a1])
        prev_ring = np.arange(base, base+n)
    # cerrar el ultimo anillo con un abanico
    ring = np.arange(len(POS)+len(new_pos)-len(vs), len(POS)+len(new_pos))
    cend = POS[vs].mean(axis=0) + axis*RINGS[-1][0]
    cend = cend + (ring.size and 0)
    cidx = len(POS) + len(new_pos)
    new_pos.append(cend); new_jt.append(cj); new_wt.append(cw)
    if NRM is not None:
        new_nrm.append(axis)
    if UV is not None:
        new_uv.append(UV[vs].mean(axis=0))
    if TAN is not None:
        new_tan.append(TAN[vs].mean(axis=0))
    for i in range(len(ring)):
        new_idx.append([cidx, ring[i], ring[(i+1) % len(ring)]])
    extended += 1
    print(f"  extendido anillo de {len(l)} verts por el eje {np.round(axis,3)}")

print(f"anillos extendidos: {extended}  verts nuevos={len(new_pos)}  tris nuevos={len(new_idx)}")
if extended == 0:
    print("NADA QUE HACER"); sys.exit(0)

POS2 = np.vstack([POS, np.array(new_pos)])
JT2 = np.vstack([JT, np.array(new_jt, dtype=JT.dtype)])
WT2 = np.vstack([WT, np.array(new_wt, dtype=WT.dtype)])
IDX2 = np.vstack([IDX, np.array(new_idx, dtype=np.int64)])
NRM2 = np.vstack([NRM, np.array(new_nrm)]) if NRM is not None else None
UV2 = np.vstack([UV, np.array(new_uv)]) if UV is not None else None
TAN2 = np.vstack([TAN, np.array(new_tan)]) if TAN is not None else None

touched = {attrs['POSITION'], attrs['JOINTS_0'], attrs['WEIGHTS_0'], pr['indices']}
for k in ('NORMAL', 'TEXCOORD_0', 'TANGENT'):
    if k in attrs:
        touched.add(attrs[k])

write_acc(j, attrs['POSITION'], POS2, comp=5126, typ='VEC3')
write_acc(j, attrs['JOINTS_0'], JT2, comp=j['accessors'][attrs['JOINTS_0']]['componentType'], typ='VEC4')
write_acc(j, attrs['WEIGHTS_0'], WT2, comp=5126, typ='VEC4')
if NRM2 is not None:
    write_acc(j, attrs['NORMAL'], NRM2, comp=5126, typ='VEC3')
if UV2 is not None:
    write_acc(j, attrs['TEXCOORD_0'], UV2, comp=5126, typ='VEC2')
if TAN2 is not None:
    write_acc(j, attrs['TANGENT'], TAN2, comp=5126, typ='VEC4')
write_acc(j, pr['indices'], IDX2, comp=5125, typ='SCALAR')

# resto de accessors, tal cual
for ai, a in enumerate(j['accessors']):
    if ai in touched or a.get('bufferView') is None:
        continue
    write_acc(j, ai, read_acc(j, b, ai), comp=a['componentType'], typ=a['type'])

# imagenes embebidas (no cuelgan de ningun accessor)
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
remap = {o: n for n, o in enumerate(used)}
j['bufferViews'] = [j['bufferViews'][o] for o in used]
for a in j['accessors']:
    if a.get('bufferView') is not None:
        a['bufferView'] = remap[a['bufferView']]
for im in j.get('images', []):
    if im.get('bufferView') is not None:
        im['bufferView'] = remap[im['bufferView']]

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
print(f"escrito {DST}  {len(out)/1e6:.2f} MB")
