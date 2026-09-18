"""Parte la G19 de Rotuma en las piezas que espera GlockWeapon.gd.

Uso:
    blender -b --python tools/build_g19_parts.py -- <entrada.glb> <salida.glb>

El archivo de origen (tools/../assets/models/g19_pistol.glb) trae la pistola DOS
veces dentro de la misma malla:

  * una copia ARMADA (centroide y en torno a 0), y
  * una copia DESPIECE tirada en el suelo (centroide y < -130 mm),
  * mas un cargador de repuesto suelto (y > 200 mm) y dos piezas flotantes
    delante de la boca.

Aqui se queda solo la copia armada, se reparte en piezas por islas de malla y
se reasientan los origenes: el gatillo gira sobre su pasador, el cargador sale
por el brocal y el cañon bascula sobre su recamara. Se endereza al convenio del
motor (morro a -Z, arriba +Y, cargador cayendo a -Y) y se escala al largo de la
malla del autor, 174 mm.
"""

import bpy
import bmesh
import math
import sys
from mathutils import Vector, Matrix

LARGO_REAL = 0.174          # largo de la malla del autor, en metros
ALTO_REAL = 0.127           # Glock 19 con miras
LINEA_CORREDERA = 0.043     # z del plano corredera/armazon
Y_ARMADA = (-0.140, 0.140)  # la copia armada vive aqui
MM = 1000.0


def islas(objeto):
    """Trocea la malla en islas (componentes conexas) y mide cada una."""
    bm = bmesh.new()
    bm.from_mesh(objeto.data)
    bm.verts.ensure_lookup_table()
    padre = list(range(len(bm.verts)))

    def raiz(a):
        while padre[a] != a:
            padre[a] = padre[padre[a]]
            a = padre[a]
        return a

    for arista in bm.edges:
        ra, rb = raiz(arista.verts[0].index), raiz(arista.verts[1].index)
        if ra != rb:
            padre[ra] = rb

    cubos = {}
    for vertice in bm.verts:
        cubos.setdefault(raiz(vertice.index), []).append(vertice.index)

    fuera = []
    for indices in cubos.values():
        mn = Vector((1e9,) * 3)
        mx = Vector((-1e9,) * 3)
        for i in indices:
            w = objeto.matrix_world @ bm.verts[i].co
            for eje in range(3):
                mn[eje] = min(mn[eje], w[eje])
                mx[eje] = max(mx[eje], w[eje])
        fuera.append({"idx": indices, "mn": mn, "mx": mx,
                      "c": (mn + mx) / 2, "d": mx - mn})
    bm.free()
    return fuera


def clasificar(todas):
    """Reparte cada isla de la copia armada en una pieza con nombre."""
    armada = [s for s in todas if Y_ARMADA[0] <= s["c"].y <= Y_ARMADA[1]]
    piezas = {"Frame": [], "Slide": [], "Barrel": [], "Magazine": [], "Trigger": []}
    for s in armada:
        c, d = s["c"], s["d"]
        # piezas flotantes del expositor: el arma no baja de -76 mm, asi que
        # todo lo que viva por debajo de -80 mm es un aro del guardamonte y dos
        # barras que el autor dejo sueltas delante de la boca.
        if s["mn"].z < -0.080:
            continue
        # plano de espesor cero que cruza toda el arma: es relleno del expositor
        if d.z < 0.0005 and d.y > 0.150:
            piezas["Frame"].append(s)
            continue
        # el cañon: un tubo redondo y grueso dentro de la corredera. El vastago
        # fino del muelle recuperador NO entra aqui: se queda con el armazon.
        if (d.y > 0.030 and c.z > 0.045 and d.x >= 0.014 and d.z >= 0.014
                and abs(d.x - d.z) < 0.004):
            piezas["Barrel"].append(s)
            continue
        # todo lo que vive por encima de la linea de la corredera
        if s["mn"].z >= LINEA_CORREDERA:
            piezas["Slide"].append(s)
            continue
        # el cargador, dentro del brocal. Lo que vive a la altura de la
        # corredera (z > 30 mm) son el reten y la palanca de desarme: al armazon.
        if c.y > 0.010 and s["mx"].z <= 0.060 and s["mn"].z <= 0.030:
            piezas["Magazine"].append(s)
            continue
        piezas["Frame"].append(s)
    return piezas


def construir(objeto, islas_de, nombre):
    """Crea un objeto con solo esas islas, conservando UV y materiales."""
    quiero = set()
    for s in islas_de:
        quiero.update(s["idx"])
    malla = objeto.data.copy()
    bm = bmesh.new()
    bm.from_mesh(malla)
    bm.verts.ensure_lookup_table()
    sobran = [bm.verts[i] for i in range(len(bm.verts)) if i not in quiero]
    bmesh.ops.delete(bm, geom=sobran, context='VERTS')
    bm.to_mesh(malla)
    bm.free()
    nuevo = bpy.data.objects.new(nombre, malla)
    nuevo.matrix_world = objeto.matrix_world.copy()
    bpy.context.collection.objects.link(nuevo)
    return nuevo


def caja(objetos):
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    for o in objetos:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for eje in range(3):
                mn[eje] = min(mn[eje], w[eje])
                mx[eje] = max(mx[eje], w[eje])
    return mn, mx


def reasentar(objeto, origen):
    """Mueve el origen de la pieza a `origen` (en mundo), dejando la malla quieta."""
    giro = objeto.matrix_world.to_3x3()
    desplazamiento = giro.inverted() @ (origen - objeto.matrix_world.translation)
    malla = objeto.data
    malla.transform(Matrix.Translation(desplazamiento))
    malla.update()
    objeto.matrix_world.translation = origen


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    entrada, salida = args[0], args[1]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=entrada)

    armas = [o for o in bpy.data.objects if o.type == 'MESH' and len(o.data.vertices) > 5000]
    if not armas:
        raise SystemExit("No encuentro la malla del arma en " + entrada)
    original = max(armas, key=lambda o: len(o.data.vertices))

    antes, _ = caja([original])

    todas = islas(original)
    print("islas totales:", len(todas))
    reparto = clasificar(todas)
    for nombre, lista in reparto.items():
        print(f"  {nombre:9s} {len(lista):4d} islas {sum(s['idx'].__len__() for s in lista):6d} verts")

    piezas = {}
    for nombre, lista in reparto.items():
        if lista:
            piezas[nombre] = construir(original, lista, nombre)

    # --- escala real y enderezado al convenio del motor -------------------
    mn, mx = caja(list(piezas.values()))
    largo = mx.y - mn.y
    escala = LARGO_REAL / largo
    print(f"largo modelo {largo * MM:.1f} mm -> escala {escala:.4f}")

    raiz = bpy.data.objects.new("Gun", None)
    bpy.context.collection.objects.link(raiz)
    for o in piezas.values():
        m = o.matrix_world.copy()
        o.parent = raiz
        o.matrix_world = m
    # el morro del autor mira a -Y; con el giro queda a +Y en Blender y el
    # exportador lo deja mirando a -Z en el motor, que es el eje que declara
    # GlockWeapon.MUZZLE_AXIS (la corredera retrocede al reves de ese eje).
    raiz.rotation_euler = (0.0, 0.0, math.pi)
    raiz.scale = (escala, escala, escala)
    bpy.context.view_layer.update()

    # cocer transformaciones: cada pieza queda en coordenadas limpias
    for o in piezas.values():
        m = o.matrix_world.copy()
        o.parent = None
        o.data.transform(m)
        o.data.update()
        o.matrix_world = Matrix.Identity(4)
    bpy.data.objects.remove(raiz, do_unlink=True)

    # fuera la malla original y cualquier resto
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o not in piezas.values():
            bpy.data.objects.remove(o, do_unlink=True)

    # --- el gatillo: se recorta del armazon por su caja -------------------
    CAJA_GATILLO = ((-0.016, 0.018), (0.0016, 0.027), (0.009,))
    armazon = piezas["Frame"]
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = armazon
    armazon.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    marca = []
    for v in armazon.data.vertices:
        w = armazon.matrix_world @ v.co
        if (CAJA_GATILLO[0][0] <= w.y <= CAJA_GATILLO[0][1]
                and CAJA_GATILLO[1][0] <= w.z <= CAJA_GATILLO[1][1]
                and abs(w.x) <= CAJA_GATILLO[2][0]):
            v.select = True
            marca.append(v.index)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    nuevas = [o for o in bpy.context.selected_objects if o.name != armazon.name]
    print("gatillo recortado:", len(marca), "vertices ->", [o.name for o in nuevas])
    if nuevas:
        gat = nuevas[0]
        gat.name = "Trigger"
        piezas["Trigger"] = gat

    # --- colocacion del origen --------------------------------------------
    # La Glock vieja trae el origen centrado en Y y Z, pero 19.8 mm a la
    # derecha del eje del arma en X. Se replica para que el encuadre del
    # viewmodel (GlockViewmodel.HIP_POS) siga valiendo sin retocar nada.
    # Esto va ANTES de reasentar los pivotes: mover la malla con los origenes
    # ya puestos descoloca las piezas.
    mn, mx = caja([o for o in bpy.data.objects if o.type == 'MESH'])
    sitio = Vector((-0.0198, 0.0, 0.0)) - (mn + mx) / 2
    for o in bpy.data.objects:
        if o.type == 'MESH':
            o.data.transform(Matrix.Translation(sitio))
            o.data.update()
    print("origen colocado: centro del arma en (-19.8, 0.0, 0.0) mm")

    # --- origenes: cada pieza gira sobre su eje de verdad -----------------
    def caja_de(o):
        mn = Vector((1e9,) * 3)
        mx = Vector((-1e9,) * 3)
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for eje in range(3):
                mn[eje] = min(mn[eje], w[eje])
                mx[eje] = max(mx[eje], w[eje])
        return mn, mx

    def reasentar(o, origen):
        o.data.transform(Matrix.Translation(-origen))
        o.data.update()
        o.matrix_world.translation = origen

    for nombre, sitio in [("Trigger", "arriba"), ("Magazine", "arriba"),
                          ("Barrel", "atras"), ("Slide", "abajo")]:
        if nombre not in piezas:
            continue
        mn, mx = caja_de(piezas[nombre])
        if sitio == "arriba":
            reasentar(piezas[nombre], Vector((0.0, mx.y, mx.z)))
        elif sitio == "atras":
            # el cañon bascula sobre la CARA DE CULATA (la recamara), que tras
            # enderezar el arma queda a -Y; la boca queda al otro extremo (+Y).
            reasentar(piezas[nombre], Vector((0.0, mn.y, (mn.z + mx.z) / 2)))
        else:
            reasentar(piezas[nombre], Vector((0.0, mx.y, mn.z)))

    # --- puntos de interes, colgados de la corredera ----------------------
    ## El arma ya enderezada mira a +Y en Blender y el exportador la deja a -Z
    ## en el motor, que es el eje que declara `GlockWeapon.MUZZLE_AXIS`. No hay
    ## que suponerlo: lo dice la malla. El cargador va DETRAS del gatillo y el
    ## cañon DELANTE de los dos, asi que +Y es la boca y -Y la culata.
    ##
    ## Tener la boca en el extremo equivocado costo dos fallos de una vez: la
    ## corredera "retrocedia" hacia el morro y el ADS giraba el arma media
    ## vuelta, porque la mira trasera caia delante de la delantera.
    ##
    ## Los puntos van sobre la linea del arma: el armazon no esta centrado en x
    ## (su centro cae a -19,8 mm).
    if "Slide" in piezas:
        slide = piezas["Slide"]
        mn, mx = caja_de(slide)
        linea_x = (mn.x + mx.x) / 2.0
        alto = mx.z
        for nombre, pos in [
            ("SightRear", Vector((linea_x, mn.y + 0.006, alto))),
            ("SightFront", Vector((linea_x, mx.y - 0.015, alto))),
            ("EjectionPort", Vector((mx.x + 0.003, mx.y - 0.075, alto))),
            ("Muzzle", Vector((linea_x, mx.y, (mn.z + mx.z) / 2))),
        ]:
            vacio = bpy.data.objects.new(nombre, None)
            bpy.context.collection.objects.link(vacio)
            vacio.parent = slide
            vacio.location = slide.matrix_world.inverted() @ pos
            vacio.rotation_mode = 'QUATERNION'
            vacio.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)

    # --- invariante: el arma entera no se ha movido de sitio --------------
    mn2, mx2 = caja([o for o in bpy.data.objects if o.type == 'MESH'])
    esperado = (mx - mn) * escala
    real = mx2 - mn2
    print(f"caja tras montar  mm: {real.x * MM:.1f} x {real.y * MM:.1f} x {real.z * MM:.1f}")
    print(f"largo real {real.y * MM:.1f} mm (objetivo {LARGO_REAL * MM:.0f})")
    print(f"alto  real {real.z * MM:.1f} mm (objetivo {ALTO_REAL * MM:.0f})")
    if abs(real.y - LARGO_REAL) > 0.003:
        raise SystemExit("El largo no cuadra: revisa la escala")

    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.name not in piezas and len(o.data.vertices) > 5000:
            bpy.data.objects.remove(o, do_unlink=True)

    bpy.ops.export_scene.gltf(
        filepath=salida,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_image_format='AUTO',
        export_yup=True,
    )
    print("escrito:", salida)


main()
