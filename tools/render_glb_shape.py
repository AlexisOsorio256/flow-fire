#!/usr/bin/env python3
"""Renderiza una malla de un GLB proyectando la geometria a mano (sin Blender).

Blender 4.0 importa mal estos GLB de Sketchfab: la jerarquia lleva escalas de
100 y 0,01, el reposo de los huesos sale a 100x y las traslaciones de animacion
se disparan, asi que el render del viewport sale como una sábana estirada. Aqui
se lee el buffer y se proyecta en Python: z-buffer propio por splatting, que es
suficiente para JUZGAR LA FORMA (que es lo unico que se pretende).

Uso: python3 render_mesh.py <glb> <salida.png> <substr_malla,...> [res]
"""
import json, struct, sys, zlib
import numpy as np

GLB, OUT = sys.argv[1], sys.argv[2]
KEEP = [s for s in sys.argv[3].split(",") if s]
RES = int(sys.argv[4]) if len(sys.argv) > 4 else 900

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


def mk_acc(j, b):
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


j, b = read_glb(GLB)
acc = mk_acc(j, b)
names = [n.get('name', '?') for n in j['nodes']]

# --- recoger vertices en bind pose (invBind aplicada) de las mallas pedidas ---
allpts = []
for m in j['meshes']:
    nm = m.get('name', '')
    if KEEP and not any(k in nm for k in KEEP):
        continue
    for pr in m['primitives']:
        V = acc(pr['attributes']['POSITION'])
        allpts.append(V)
        print(f"  {nm}: {len(V)} verts  {j['accessors'][pr['indices']]['count']//3} tris")
if not allpts:
    print("NADA SELECCIONADO"); sys.exit(1)
P = np.vstack(allpts)
print(f"total {len(P)} verts")
mn = P.min(axis=0); mx = P.max(axis=0)
print(f"bbox min={np.round(mn,3)} max={np.round(mx,3)} tam={np.round(mx-mn,3)}")

# --- proyectar en 3 vistas ortograficas y componer una tira ---
def render_view(P, u, v, w, res=RES):
    """u,v = ejes de pantalla; w = eje de profundidad. Splatting con z-buffer."""
    W = int(res*(mx[u]-mn[u])/max(mx-mn))+8
    H = int(res*(mx[v]-mn[v])/max(mx-mn))+8
    W = max(W, 32); H = max(H, 32)
    img = np.full((H, W), 1.0)
    zbuf = np.full((H, W), 1e18)
    px = ((P[:, u]-mn[u])/(mx[u]-mn[u]+1e-12)*(W-9)).astype(int)+4
    py = ((P[:, v]-mn[v])/(mx[v]-mn[v]+1e-12)*(H-9)).astype(int)+4
    pz = P[:, w]
    # splat 2x2 para que las mallas densas no dejen huecos
    for dx in (0, 1):
        for dy in (0, 1):
            xx = np.clip(px+dx, 0, W-1); yy = np.clip(py+dy, 0, H-1)
            flat = yy*W+xx
            order = np.argsort(-pz)
            img.flat[flat[order]] = 0.25
    return img


views = [(0, 2, 1, "frente X-Z"), (1, 2, 0, "lado Y-Z"), (0, 1, 2, "planta X-Y")]
imgs = []
for u, v, w, lab in views:
    im = render_view(P, u, v, w)
    print(f"  vista {lab}: {im.shape[1]}x{im.shape[0]}")
    imgs.append(im)

H = max(im.shape[0] for im in imgs)
W = sum(im.shape[1] for im in imgs)
canvas = np.ones((H, W))
x = 0
for im in imgs:
    canvas[:im.shape[0], x:x+im.shape[1]] = im
    x += im.shape[1]
print(f"lienzo {W}x{H}")

# --- escribir PNG en escala de grises (sin dependencias) ---
bw = (np.clip(canvas, 0, 1)*255).astype(np.uint8)
raw = b''.join(b'\x00' + bw[r].tobytes() for r in range(H))
def chunk(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t+d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 0, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(raw, 6))
png += chunk(b'IEND', b'')
open(OUT, 'wb').write(png)
print("escrito", OUT)
