"""Prepara un arma GLB para el viewmodel: piezas sueltas con su propio origen.

    blender -b --python tools/make_weapon_parts.py -- <entrada.glb> <salida.glb> <glock|de>

Vale para cualquier pistola cuyas piezas ya vengan separadas por el autor como
nodos con nombre. Los nombres del origen se agrupan en las piezas que entiende
el juego:

    Frame  armazon (y todo lo que no se mueve: cachas, seguros, botones)
    Slide  corredera
    Barrel canon (se queda quieto)
    Trigger gatillo
    Magazine cargador

PROBLEMA QUE RESUELVE

Las piezas comparten el MISMO origen y su geometria esta horneada en un espacio
comun. Asi no se puede mover una pieza: el cargador giraria alrededor del arma
entera en vez de alrededor de si mismo.
-> Se hornea la geometria en su posicion de mundo, se traslada para que el
   origen de cada pieza caiga en su punto de giro, y ese desplazamiento queda
   en el transform del nodo.

Ademas anade los puntos que el juego necesita y el modelo no trae como pieza:
Muzzle, EjectionPort y las miras que falten, medidos sobre la malla (no
inventados) y colgados de la corredera, asi que viajan con ella.

ORDEN DEL PROCESO (importa)
  1. agrupar mallas por pieza
  2. colgarlas de la raiz del modelo CONSERVANDO su transform de mundo
  3. medir y hornear en mundo, rebasar el origen de cada pieza
  4. puntos mecanicos y export

Anadir un arma = anadir una entrada en ARMAS. No hay que tocar el juego.
"""
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC, DST = argv[0], argv[1]
ARMA = argv[2] if len(argv) > 2 else "glock"

# Tabla por arma: los NOMBRES de los nodos del origen y la altura del agarre.
ARMAS = {
    "glock": {
        "piezas": {
            "Gun_Slide": "Slide",
            "Gun_Body": "Frame",
            "Magazine": "Magazine",
        },
        "agarre": 0.12,
    },
    "de": {
        "piezas": {
            "Slide_low": "Slide",
            "SlidePart_low": "Slide",
            "SlideHolder_low": "Slide",
            "Safety_low": "Slide",
            "BoltMain_low": "Slide",
            "BoltAdd_low": "Slide",
            "BoltBack_low": "Slide",
            "BoltButton_low": "Slide",
            "Barrel_low": "Barrel",
            "Trigger_low": "Trigger",
            "Magazine_low": "Magazine",
            "MagazineBase_low": "Magazine",
            "BaseInside_low": "Magazine",
            "Bullet_low": "Magazine",
            "BulletCase_low": "Magazine",
            "RearSight_low": "Slide",
            "FrontSight_low": "Slide",
        },
        "agarre": 0.10,
    },
}
if ARMA not in ARMAS:
    raise SystemExit("arma desconocida: %s (usa %s)" % (ARMA, list(ARMAS)))
CFG = ARMAS[ARMA]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

mallas = [o for o in bpy.data.objects if o.type == "MESH"]
# La jerarquia del autor (con su conversion de ejes y su escala) se conserva.
raiz_modelo = next((o for o in bpy.data.objects if o.parent is None), None)
if raiz_modelo is None:
    raise SystemExit("el GLB no trae raiz de escena")
conservar = [raiz_modelo]
contenedor = raiz_modelo
while len(contenedor.children) == 1 and contenedor.children[0].type == "EMPTY":
    contenedor = contenedor.children[0]
    conservar.append(contenedor)
print("RAIZ:", raiz_modelo.name, "-> contenedor:", contenedor.name)


def nombre_de(obj):
    return (obj.parent.name if obj.parent else obj.name).split(".")[0]


# --- 1. agrupar -------------------------------------------------------------
grupos = {}
for obj in mallas:
    grupos.setdefault(CFG["piezas"].get(nombre_de(obj), "Frame"), []).append(obj)
print("AGRUPADAS EN:", {k: len(v) for k, v in grupos.items()})

# Las miras se localizan por nombre ANTES de fundirlas en la corredera: hacen
# falta para los puntos SightRear/SightFront.
MIRAS = {"SightRear": ("RearSight", "SightRear"), "SightFront": ("FrontSight", "SightFront")}

# --- 2. colgar de la raiz conservando el transform de mundo -----------------
for pieza, objs in grupos.items():
    for o in objs:
        mundo = o.matrix_world.copy()
        o.parent = contenedor
        o.matrix_world = mundo
for o in list(bpy.data.objects):
    if o.type == "EMPTY" and o not in conservar:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.update()


# --- 3. medir, hornear a mundo y rebasar ------------------------------------
def caja_mundo(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    co = [v.co.copy() for v in bm.verts]
    bm.free()
    if not co:
        return None
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    return lo, hi


cajas = {}
for pieza, objs in grupos.items():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        c = caja_mundo(o)
        if c is None:
            continue
        for i in range(3):
            lo[i] = min(lo[i], c[0][i])
            hi[i] = max(hi[i], c[1][i])
    cajas[pieza] = (lo, hi)

todo_lo = Vector((1e9, 1e9, 1e9))
todo_hi = Vector((-1e9, -1e9, -1e9))
for lo, hi in cajas.values():
    for i in range(3):
        todo_lo[i] = min(todo_lo[i], lo[i])
        todo_hi[i] = max(todo_hi[i], hi[i])
tam = todo_hi - todo_lo
eje_canon = max(range(3), key=lambda i: tam[i])
eje_arriba = max([i for i in range(3) if i != eje_canon], key=lambda i: tam[i])
print("EJES: canon=%s arriba=%s  tam=%s" % (
    "XYZ"[eje_canon], "XYZ"[eje_arriba], [round(x, 3) for x in tam]))

# Pivote del Frame: a la altura del agarre y sobre el cargador, que es quien
# dice donde esta la empunadura. Es el punto donde el arma cabecea en la mano.
agarre_altura = todo_lo[eje_arriba] + tam[eje_arriba] * CFG["agarre"]
centro_mag = (cajas["Magazine"][0] + cajas["Magazine"][1]) / 2.0 if "Magazine" in cajas else None
centro_arma = (todo_lo + todo_hi) / 2.0


def pivote_de(pieza):
    lo, hi = cajas[pieza]
    centro = (lo + hi) / 2.0
    if pieza == "Frame":
        p = Vector(centro)
        p[eje_arriba] = agarre_altura
        p[eje_canon] = centro_mag[eje_canon] if centro_mag is not None else centro[eje_canon]
        return p
    return centro


# Centros de las miras, medidos antes de fundirlas en la corredera.
centros_miras = {}
for etiqueta, nombres in MIRAS.items():
    for o in mallas:
        if nombre_de(o) in nombres:
            c = caja_mundo(o)
            if c is not None:
                centros_miras[etiqueta] = (c[0] + c[1]) / 2.0
            break

info = []
for pieza, objs in grupos.items():
    p = pivote_de(pieza)
    for o in objs:
        o.data.transform(o.matrix_world)
        o.data.transform(Matrix.Translation(-p))
        o.matrix_world = Matrix.Translation(p)
    # Una sola malla por pieza: las demas se funden en la primera.
    principal = objs[0]
    if len(objs) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = principal
        bpy.ops.object.join()
    principal.name = pieza
    principal.data.name = pieza
    info.append((pieza, len(principal.data.polygons), p))
bpy.context.view_layer.update()
print("PIEZAS FINALES:", [o.name for o in bpy.data.objects if o.type == "MESH"])


# --- 4. puntos mecanicos medidos sobre la malla -----------------------------
def caja_de(nombre):
    o = bpy.data.objects.get(nombre)
    return caja_mundo(o) if o is not None and o.type == "MESH" else None


slide_caja = caja_de("Slide")
if slide_caja is None:
    raise SystemExit("no hay pieza Slide: no se pueden colgar boca ni miras")
s_lo, s_hi = slide_caja
slide_obj = bpy.data.objects["Slide"]
piv_slide = slide_obj.matrix_world.translation.copy()
# El frente es el lado de la corredera mas lejos del cargador.
mag_centro = centro_mag if centro_mag is not None else centro_arma
frente_es_mayor = (s_hi[eje_canon] - mag_centro[eje_canon]) > (mag_centro[eje_canon] - s_lo[eje_canon])


def punto_boca():
    fuente = caja_de("Barrel") or slide_caja
    lo, hi = fuente
    p = Vector((lo + hi) / 2.0)
    p[eje_canon] = hi[eje_canon] if frente_es_mayor else lo[eje_canon]
    return p


def punto_mira(trasera):
    etiqueta = "SightRear" if trasera else "SightFront"
    if etiqueta in centros_miras:
        return centros_miras[etiqueta]
    lo, hi = slide_caja
    p = Vector((lo + hi) / 2.0)
    p[eje_canon] = lo[eje_canon] if (trasera == frente_es_mayor) else hi[eje_canon]
    p[eje_arriba] = hi[eje_arriba]
    return p


def punto_puerto():
    """Puerto de expulsion: lado derecho, arriba y por delante de la recamara."""
    lo, hi = slide_caja
    p = Vector((lo + hi) / 2.0)
    p[0] = hi[0] if hi[0] > -lo[0] else lo[0]
    p[eje_arriba] = lo[eje_arriba] + (hi[eje_arriba] - lo[eje_arriba]) * 0.78
    return p


PUNTOS = {}
if "Muzzle" not in bpy.data.objects:
    PUNTOS["Muzzle"] = punto_boca()
for nombre, trasera in (("SightFront", False), ("SightRear", True)):
    if nombre not in bpy.data.objects:
        PUNTOS[nombre] = punto_mira(trasera)
if "EjectionPort" not in bpy.data.objects:
    PUNTOS["EjectionPort"] = punto_puerto()

for nombre, punto in PUNTOS.items():
    vacio = bpy.data.objects.new(nombre, None)
    bpy.context.collection.objects.link(vacio)
    vacio.parent = slide_obj
    vacio.matrix_parent_inverse = Matrix.Identity(4)
    vacio.location = punto - piv_slide
    print("PUNTO %-14s local %s" % (nombre, str([round(x, 4) for x in vacio.location])))

print("%-10s %7s  %-30s" % ("pieza", "caras", "pivote"))
for pieza, caras, p in info:
    print("%-10s %7d  %-30s" % (pieza, caras, str([round(x, 3) for x in p])))

# --- 5. exportar -----------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type in ("MESH", "EMPTY"):
        o.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=DST,
    export_format="GLB",
    use_selection=True,
    export_apply=False,
    export_yup=True,
)
print("EXPORTADO:", DST, "| arma:", ARMA)
