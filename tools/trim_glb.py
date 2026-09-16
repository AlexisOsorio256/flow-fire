#!/usr/bin/env python3
"""Limpia un GLB: quita materiales huerfanos, imagenes/texturas sin uso y
samplers sin uso, y reescribe el buffer solo con lo que queda.

Se necesita porque al extraer los brazos de un pack de primera persona los
materiales del arma siguen declarados y retienen sus texturas: medido en el 9mm
de 1Matzh, quedaban 7 materiales y 18 imagenes (66 MB) para 2 mallas.

Uso: python3 trim_glb.py <entrada.glb> <salida.glb>
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


def read_acc(j, b, i):
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


buf = bytearray()


def write_acc(j, acc_index, arr, comp, typ):
    a = j['accessors'][acc_index]
    arr = np.asarray(arr)
    fmt, sz = CT[comp]; n = NC[typ]
    arr = arr.reshape(-1) if typ == 'SCALAR' else (arr[:, None] if arr.ndim == 1 else arr)
    raw = arr.astype(np.dtype('<'+fmt)).tobytes()
    while len(buf) % 4:
        buf.append(0)
    off = len(buf); buf.extend(raw)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)})
    a['bufferView'] = len(j['bufferViews'])-1
    a['byteOffset'] = 0
    j['accessors'][acc_index] = j['accessors'][acc_index]
    a['count'] = int(arr.shape[0])


SRC, DST = sys.argv[1], sys.argv[2]
j, b = read_glb(SRC)

# --- 1. materiales realmente usados por las mallas ---
used_mats = set()
for m in j.get('meshes', []):
    for pr in m['primitives']:
        if 'material' in pr:
            used_mats.add(pr['material'])
print(f"materiales: {len(j.get('materials', []))} declarados, {len(used_mats)} usados")
kept = sorted(used_mats)
rm_mat = {o: n for n, o in enumerate(kept)}
j['materials'] = [j['materials'][o] for o in kept]
for m in j.get('meshes', []):
    for pr in m['primitives']:
        if 'material' in pr:
            pr['material'] = rm_mat[pr['material']]

# --- 2. texturas que usan esos materiales ---
used_tex = set()
for m in j['materials']:
    pbr = m.get('pbrMetallicRoughness', {})
    for k in ('baseColorTexture', 'metallicRoughnessTexture'):
        if k in pbr:
            used_tex.add(pbr[k]['index'])
    for k in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
        if k in m:
            used_tex.add(m[k]['index'])
print(f"texturas: {len(j.get('textures', []))} declaradas, {len(used_tex)} usadas")
kept_t = sorted(used_tex)
rm_tex = {o: n for n, o in enumerate(kept_t)}
j['textures'] = [j['textures'][o] for o in kept_t]
for m in j['materials']:
    pbr = m.get('pbrMetallicRoughness', {})
    for k in ('baseColorTexture', 'metallicRoughnessTexture'):
        if k in pbr:
            pbr[k]['index'] = rm_tex[pbr[k]['index']]
    for k in ('normalTexture', 'occlusionTexture', 'emissiveTexture'):
        if k in m:
            m[k]['index'] = rm_tex[m[k]['index']]

# --- 3. imagenes usadas ---
used_img = {t['source'] for t in j['textures'] if 'source' in t}
print(f"imagenes: {len(j.get('images', []))} declaradas, {len(used_img)} usadas")
kept_i = sorted(used_img)
rm_img = {o: n for n, o in enumerate(kept_i)}
j['images'] = [j['images'][o] for o in kept_i]
for t in j['textures']:
    if 'source' in t:
        t['source'] = rm_img[t['source']]

# --- 4. samplers usados ---
if 'samplers' in j:
    used_s = {t['sampler'] for t in j['textures'] if 'sampler' in t}
    if used_s:
        kept_s = sorted(used_s)
        rm_s = {o: n for n, o in enumerate(kept_s)}
        j['samplers'] = [j['samplers'][o] for o in kept_s]
        for t in j['textures']:
            if 'sampler' in t:
                t['sampler'] = rm_s[t['sampler']]

# --- 5. reescribir el buffer ---
for ai, a in enumerate(j['accessors']):
    if a.get('bufferView') is not None:
        write_acc(j, ai, read_acc(j, b, ai), a['componentType'], a['type'])
for img in j['images']:
    bv = j['bufferViews'][img['bufferView']]
    o = bv.get('byteOffset', 0)
    raw = b[o:o+bv['byteLength']]
    while len(buf) % 4:
        buf.append(0)
    off = len(buf); buf.extend(raw)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)})
    img['bufferView'] = len(j['bufferViews'])-1

used = sorted({a['bufferView'] for a in j['accessors'] if a.get('bufferView') is not None} |
              {im['bufferView'] for im in j['images'] if 'bufferView' in im})
rm = {o: n for n, o in enumerate(used)}
j['bufferViews'] = [j['bufferViews'][o] for o in used]
for a in j['accessors']:
    if a.get('bufferView') is not None:
        a['bufferView'] = rm[a['bufferView']]
for im in j['images']:
    if 'bufferView' in im:
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
print(f"escrito {DST}  {len(out)/1e6:.2f} MB")
print(f"  materiales={len(j['materials'])} texturas={len(j.get('textures',[]))} imagenes={len(j['images'])}")
