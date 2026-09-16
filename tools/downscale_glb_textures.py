#!/usr/bin/env python3
"""Reduce las texturas embebidas de un GLB a una resolucion maxima.

Motivo medido: los brazos del 9mm de 1Matzh traen mapas de 4096x4096 (46 MB
entre 6 imagenes). El proyecto renderiza con el perfil **Mobile** y su asset
anterior usaba 1024x1024; 4K es desproporcionado y castiga VRAM y tiempo de
carga en Android. 2048 conserva el detalle que se ve a la distancia del
viewmodel (la camara esta a ~0,5 m, la manga ocupa una fraccion de pantalla).

Uso: python3 downscale_glb_textures.py <entrada.glb> <salida.glb> [max_px]
"""
import json, struct, sys, os, subprocess, tempfile

MAXPX = int(sys.argv[3]) if len(sys.argv) > 3 else 2048


def read_glb(p):
    d = open(p, 'rb').read()
    assert d[:4] == b'glTF'
    off = 12; js = None; b = b''
    while off < len(d):
        ln, ty = struct.unpack_from('<II', d, off)
        ch = d[off+8:off+8+ln]
        if ty == 0x4E4F534A:
            js = json.loads(ch)
        elif ty == 0x004E4942:
            b = ch
        off += 8 + ln
    return js, b


def png_size(raw):
    if raw[:8] == b'\x89PNG\r\n\x1a\n':
        w, h = struct.unpack('>II', raw[16:24])
        return w, h
    return None


def jpeg_size(raw):
    i = 2
    while i < len(raw)-9:
        if raw[i] != 0xFF:
            i += 1; continue
        m = raw[i+1]
        if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            h, w = struct.unpack('>HH', raw[i+5:i+9])
            return w, h
        if m in (0xD8, 0xD9) or 0xD0 <= m <= 0xD7:
            i += 2; continue
        ln = struct.unpack('>H', raw[i+2:i+4])[0]
        i += 2 + ln
    return None


SRC, DST = sys.argv[1], sys.argv[2]
j, b = read_glb(SRC)

new_imgs = []
changed = 0
with tempfile.TemporaryDirectory() as td:
    for i, im in enumerate(j.get('images', [])):
        bv = j['bufferViews'][im['bufferView']]
        o = bv.get('byteOffset', 0)
        raw = b[o:o+bv['byteLength']]
        if im.get('mimeType') == 'image/jpeg':
            size = jpeg_size(raw)
        else:
            size = png_size(raw)
        if size is None:
            new_imgs.append(raw); continue
        w, h = size
        if max(w, h) <= MAXPX:
            new_imgs.append(raw); continue
        src = os.path.join(td, f'in{i}.png')
        dst = os.path.join(td, f'out{i}.png')
        open(src, 'wb').write(raw)
        r = subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', src,
                            '-vf', f'scale={MAXPX}:{MAXPX}:flags=lanczos', dst],
                           capture_output=True)
        if r.returncode != 0 or not os.path.exists(dst):
            print(f"  img{i} {w}x{h} -> FALLO, se deja igual")
            new_imgs.append(raw); continue
        out = open(dst, 'rb').read()
        print(f"  img{i} {w}x{h} -> {MAXPX}x{MAXPX}  {len(raw)/1e6:.2f} -> {len(out)/1e6:.2f} MB")
        new_imgs.append(out); changed += 1

print(f"imagenes reducidas: {changed}")

# reescribir el buffer entero
buf = bytearray()
CT = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_acc(i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    fmt, sz = CT[a['componentType']]; n = NC[a['type']]
    st = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride') or (sz*n)
    if stride == sz*n:
        o = __import__('numpy').frombuffer(b[st:st+a['count']*stride], dtype=__import__('numpy').dtype('<'+fmt))
    else:
        o = __import__('numpy').empty(a['count']*n, dtype=__import__('numpy').dtype('<'+fmt))
        for k in range(a['count']):
            o[k*n:(k+1)*n] = struct.unpack_from('<'+fmt*n, b, st+k*stride)
    return o


for ai, a in enumerate(j['accessors']):
    if a.get('bufferView') is None:
        continue
    arr = read_acc(ai)
    raw = arr.tobytes()
    while len(buf) % 4:
        buf.append(0)
    off = len(buf); buf.extend(raw)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)})
    a['bufferView'] = len(j['bufferViews'])-1
    a['byteOffset'] = 0

for i, im in enumerate(j['images']):
    raw = new_imgs[i]
    while len(buf) % 4:
        buf.append(0)
    off = len(buf); buf.extend(raw)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)})
    im['bufferView'] = len(j['bufferViews'])-1
    im['mimeType'] = 'image/png'

used = sorted({a['bufferView'] for a in j['accessors'] if a.get('bufferView') is not None} |
              {im['bufferView'] for im in j['images']})
rm = {o: n for n, o in enumerate(used)}
j['bufferViews'] = [j['bufferViews'][o] for o in used]
for a in j['accessors']:
    if a.get('bufferView') is not None:
        a['bufferView'] = rm[a['bufferView']]
for im in j['images']:
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
