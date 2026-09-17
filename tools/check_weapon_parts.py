"""Verifica un GLB de arma: piezas, tamano real y puntos mecanicos.

    blender -b --python tools/check_weapon_parts.py -- <glb>

Imprime, en el sistema de ejes en que Blender importa el GLB (arriba = +Z,
largo = el eje mayor) y en milimetros:
  - la caja de cada pieza y del arma entera,
  - donde cae cada punto mecanico (boca, miras, puerto),
  - las relaciones que deben cumplirse: las miras dentro de la corredera, el
    puerto por encima del eje y la boca lejos del brocal.

Sirve para detectar un montaje mal medido sin abrir el editor.
"""
import sys

import bpy
import bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)


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


PUNTOS_NOMBRES = ("Muzzle", "SightRear", "SightFront", "EjectionPort")
piezas = {}
puntos = {}
todo_lo = Vector((1e9, 1e9, 1e9))
todo_hi = Vector((-1e9, -1e9, -1e9))
for o in bpy.data.objects:
    clave = o.name.split(".")[0]
    if clave in PUNTOS_NOMBRES:
        # Puede ser una pieza con malla o un nodo vacio: en los dos casos vale
        # su posicion en el mundo.
        if o.type == "MESH":
            c = caja_mundo(o)
            puntos[clave] = (c[0] + c[1]) / 2.0 if c else o.matrix_world.translation.copy()
        else:
            puntos[clave] = o.matrix_world.translation.copy()
        continue
    if o.type != "MESH":
        continue
    c = caja_mundo(o)
    if c is None:
        continue
    piezas[clave] = c
    for i in range(3):
        todo_lo[i] = min(todo_lo[i], c[0][i])
        todo_hi[i] = max(todo_hi[i], c[1][i])

tam = todo_hi - todo_lo
print("==", SRC.split("/")[-1])
print("ARMA  tam(mm) %s" % [round(x * 1000, 1) for x in tam])
print("PIEZAS:")
for n, (lo, hi) in sorted(piezas.items()):
    print("   %-12s centro(mm) %-30s tam(mm) %s" % (
        n, str([round(x * 1000, 1) for x in ((lo + hi) / 2.0)]),
        str([round(x * 1000, 1) for x in (hi - lo)])))
print("PUNTOS:")
for n, p in sorted(puntos.items()):
    print("   %-14s %s" % (n, str([round(x * 1000, 1) for x in p])))

largo = max(range(3), key=lambda i: tam[i])
arriba = max([i for i in range(3) if i != largo], key=lambda i: tam[i])
print("EJES: largo=%s arriba=%s" % ("XYZ"[largo], "XYZ"[arriba]))
if "Barrel" in piezas:
    print("canon: %.1f mm de largo" % ((piezas["Barrel"][1][largo] - piezas["Barrel"][0][largo]) * 1000))
if "Magazine" in piezas:
    print("cargador: %.1f mm de alto" % ((piezas["Magazine"][1][arriba] - piezas["Magazine"][0][arriba]) * 1000))


def dentro(punto, caja, margen):
    lo, hi = caja
    return all(lo[i] - margen <= punto[i] <= hi[i] + margen for i in range(3))


margen = 0.06 * max(tam)
ok = True
for nombre in ("SightRear", "SightFront"):
    if nombre in puntos and "Slide" in piezas:
        r = dentro(puntos[nombre], piezas["Slide"], margen)
        print("%-22s dentro de la corredera: %s" % (nombre, "OK" if r else "MAL"))
        ok = ok and r
if "Muzzle" in puntos and "Magazine" in piezas:
    # La boca tiene que estar en el extremo OPUESTO al cargador, que vive en la
    # empunadura. En una pistola el cargador esta detras, asi que la boca queda
    # en la mitad delantera: comparar contra "mitad del arma" es lo correcto,
    # no contra el largo entero.
    mag = (piezas["Magazine"][0] + piezas["Magazine"][1]) / 2.0
    boca = puntos["Muzzle"][largo]
    d = abs(boca - mag[largo])
    r = d > tam[largo] * 0.35
    print("%-22s lejos del brocal (%.0f mm de %.0f): %s" % (
        "Muzzle", d * 1000, tam[largo] * 1000, "OK" if r else "MAL"))
    ok = ok and r
if "EjectionPort" in puntos and "Slide" in piezas:
    c = (piezas["Slide"][0] + piezas["Slide"][1]) / 2.0
    r = puntos["EjectionPort"][arriba] > c[arriba]
    print("%-22s por encima del eje: %s" % ("EjectionPort", "OK" if r else "MAL"))
    ok = ok and r
print("RESULTADO:", "coherente" if ok else "HAY ALGO MAL")
