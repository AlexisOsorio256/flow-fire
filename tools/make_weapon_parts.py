"""Prepara una pistola GLB para el viewmodel: piezas sueltas + puntos mecanicos.

    blender -b --python tools/make_weapon_parts.py -- <entrada.glb> <salida.glb> <arma>

Entrada: una pistola SIN esqueleto, con las piezas ya separadas por el autor
como nodos (caso de Urpo 9mm: Gun_Slide / Gun_Body / Magazine).

PROBLEMA QUE RESUELVE

1. Los nodos comparten el MISMO origen (0,0,0) y su geometria esta horneada en
   ese espacio comun. Asi no se puede mover una pieza: el cargador giraria
   alrededor del arma entera en vez de alrededor de si mismo.
   -> Se traslada la geometria para que el origen de cada pieza caiga en el
      punto de giro correcto, y ese desplazamiento queda en el transform del nodo.

2. No hay puntos para la boca, el puerto de expulsion ni las miras.
   -> Se anaden como nodos vacios hijos de la corredera, con coordenadas
      MEDIDAS sobre esta malla (no inventadas), asi que viajan con ella.

El resultado se ve identico al original, pero a partir de aqui mover una pieza
es escribir SU transform, y editar su geometria es tocar UNA malla.

EJES DEL ARMA (Blender, medidos):  +Y boca · +Z alza · +X derecha
PUNTOS MEDIDOS sobre la malla de Urpo (Blender):
  boca             (-0.153,  0.741,  0.406)
  mira delantera   (-0.153,  0.680,  0.556)
  mira trasera     (-0.153, -0.580,  0.560)
  puerto           (-0.039, -0.080,  0.465)
"""
import sys
import bpy
import bmesh
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC, DST = argv[0], argv[1]
ARMA = argv[2] if len(argv) > 2 else "weapon"

# Puntos de la malla de Urpo 9mm, medidos vertice a vertice.
PUNTOS = {
    "Muzzle": Vector((-0.153, 0.741, 0.406)),
    "SightFront": Vector((-0.153, 0.680, 0.556)),
    "SightRear": Vector((-0.153, -0.580, 0.560)),
    "EjectionPort": Vector((-0.039, -0.080, 0.465)),
}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)


def caja(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    co = [v.co for v in bm.verts]
    nv = len(co)
    bm.free()
    if not co:
        return None
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    return lo, hi, nv


def nombre_semantico(obj):
    bruto = obj.parent.name if obj.parent else obj.name
    base = bruto.split(".")[0].replace("Gun_", "").replace("_low", "")
    return {"Body": "Frame", "Slide": "Slide", "Magazine": "Magazine"}.get(base, base)


piezas = [o for o in bpy.data.objects if o.type == "MESH"]
todo_lo = Vector((1e9, 1e9, 1e9))
todo_hi = Vector((-1e9, -1e9, -1e9))
for o in piezas:
    c = caja(o)
    if not c:
        continue
    for i in range(3):
        todo_lo[i] = min(todo_lo[i], c[0][i])
        todo_hi[i] = max(todo_hi[i], c[1][i])
print("CAJA DEL ARMA min", [round(x, 3) for x in todo_lo], "max", [round(x, 3) for x in todo_hi])
print("LARGO %.3f  ALTO %.3f  ANCHO %.3f" % (
    todo_hi.y - todo_lo.y, todo_hi.z - todo_lo.z, todo_hi.x - todo_lo.x))

# Pivote del cabeceo: parte alta de la empunadura (donde la mano agarra).
agarre_y = todo_lo.y + (todo_hi.y - todo_lo.y) * 0.30
agarre_z = todo_lo.z + (todo_hi.z - todo_lo.z) * 0.12

info = []
for obj in piezas:
    c = caja(obj)
    if not c:
        continue
    lo, hi, nv = c
    nombre = nombre_semantico(obj)
    centro = (lo + hi) / 2.0
    p = Vector((centro.x, agarre_y, agarre_z)) if nombre == "Frame" else centro
    obj.data.transform(Matrix.Translation(-p))
    obj.matrix_world = Matrix.Translation(p)
    obj.name = nombre
    obj.data.name = nombre
    info.append((nombre, nv, len(obj.data.polygons), lo, hi, p))

print("%-12s %6s %6s  %-30s %-30s" % ("pieza", "verts", "caras", "caja min", "pivote"))
for nombre, nv, nf, lo, hi, p in info:
    print("%-12s %6d %6d  %-30s %-30s" % (
        nombre, nv, nf, str([round(x, 3) for x in lo]), str([round(x, 3) for x in p])))

# Puntos mecanicos: hijos de la corredera, en coordenadas de SU pivote.
slide = bpy.data.objects.get("Slide")
if slide is None:
    raise SystemExit("no hay pieza Slide; no se pueden colgar boca ni miras")
piv_slide = Vector(slide.matrix_world.translation)
for nombre, punto in PUNTOS.items():
    vacio = bpy.data.objects.new(nombre, None)
    bpy.context.collection.objects.link(vacio)
    vacio.parent = slide
    vacio.matrix_parent_inverse = Matrix.Identity(4)
    vacio.location = punto - piv_slide
    print("PUNTO %-14s local %s" % (nombre, str([round(x, 4) for x in vacio.location])))

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
