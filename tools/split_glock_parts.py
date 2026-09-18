"""Segunda pasada sobre el GLB del arma: separa gatillo, canon y herrajes.

    blender -b --python tools/split_glock_parts.py -- <entrada.glb> <salida.glb>

PROBLEMA QUE RESUELVE

`tools/make_weapon_parts.py` agrupa por NOMBRE de nodo del autor, y el autor
metio en el nodo "Magazine" todo lo que va suelto dentro del armazon:

    el cargador de verdad, el gatillo (diente + barra), el muelle recuperador
    y los herrajes del armazon (caja del gatillo, fiador, reten del cargador).

Consecuencias que se veian en el juego:
  - al expulsar el cargador se iba con el TODO, gatillo incluido;
  - el gatillo no se movia porque no existia como pieza;
  - no habia canon: el puerto de eyeccion dejaba ver un bloque negro.

Este script parte ese nodo por ISLAS DE MALLA (trozos sin unir entre si) y
decide a donde va cada isla midiendo, no adivinando:

  Trigger        dentro de la caja del gatillo (delante-abajo del armazon)
  RecoilSpring   delante del armazon, a la altura del muelle, hasta la boca
  Magazine       pegado al cuerpo del cargador (distancias, no solo cajas)
  FrameDetail    todo lo demas: es armazon y no lo mueve nadie

Ademas MODELA el canon, que el asset no trae: tubo + recamara con su eje en
la linea de la boca (`Muzzle`) y origen en la cara de culata, que es donde
gira. Un canon de Glock 19 son 102 mm, el mismo largo del original.

Lo que NO hace: tocar la jerarquia del autor, los materiales ni las texturas.
Las piezas nuevas salen del MISMO nodo del que se extraen (mismo material y
mismas UV) para que no cambie nada de lo que ya se veia bien.
"""
import math
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, kdtree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC, DST = argv[0], argv[1]

## Nodo del autor que hay que partir, y donde vive el resto de las piezas.
GRAB_BAG = "Magazine"
FRAME = "Frame"
SLIDE = "Slide"

## Eje del anima y boca, medidos sobre el propio asset (nodo `Muzzle`).
BORE_X = -0.153
BORE_Z = 0.406
MUZZLE_Y = 0.7415

## Glock 19 real, en unidades del modelo (1 unidad = 126,06 mm).
MM = 1.0 / 126.06
BARREL_LARGO = 102.0 * MM
BARREL_RADIO = 6.8 * MM
PUNTA_RADIO = 4.6 * MM
CULATA_RADIO = 5.3 * MM

## Cajas de decision, en espacio de mundo del modelo tal cual se importa.
TRIGGER_BOX = {
    "y": (-0.46, 0.16),
    "z": (-0.02, 0.26),
    "x": (-0.23, -0.08),
}
## El muelle recuperador va por delante del armazon y por debajo del anima.
SPRING_BOX = {
    "y_min": 0.20,
    "z": (0.22, 0.37),
}
## Umbral de cercania con el cuerpo del cargador, en unidades del modelo.
TOQUE = 0.02
## Techo del cargador: por encima de esta z solo vive el armazon (la caja del
## gatillo toca los labios del cargador, asi que la cercania sola no decide).
TECHO_CARGADOR = 0.24


def islas_de(me, mundo):
    """Trozos de malla sin unir entre si, con su caja en mundo."""
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    vistas = set()
    salida = []
    for v in bm.verts:
        if v.index in vistas:
            continue
        pila = [v]
        vistas.add(v.index)
        comp = []
        while pila:
            act = pila.pop()
            comp.append(act.index)
            for arista in act.link_edges:
                otro = arista.other_vert(act)
                if otro.index not in vistas:
                    vistas.add(otro.index)
                    pila.append(otro)
        lo = Vector((1e9,) * 3)
        hi = Vector((-1e9,) * 3)
        for i in comp:
            w = mundo @ me.vertices[i].co
            for k in range(3):
                lo[k] = min(lo[k], w[k])
                hi[k] = max(hi[k], w[k])
        salida.append({"verts": sorted(comp), "lo": lo, "hi": hi})
    bm.free()
    return salida


def caja(isla):
    return isla["lo"], isla["hi"]


def centro(isla):
    return (isla["lo"] + isla["hi"]) * 0.5


def dentro(isla, limites):
    lo, hi = caja(isla)
    ejes = {"x": 0, "y": 1, "z": 2}
    for eje, (a, b) in limites.items():
        k = ejes[eje]
        if a > lo[k] or b < hi[k]:
            return False
    return True


def recortar(origen, indices, nombre, padre):
    """Objeto nuevo con esas islas, conservando material, UV y transform.

    OJO con `matrix_parent_inverse`: es un invento de Blender y el glTF no lo
    tiene. Si se usa, el origen de la pieza se va al exportar. Aqui el padre se
    asigna con el inverse a identidad y es Blender el que resuelve el transform
    local, que es lo unico que viaja en el archivo.
    """
    me = origen.data.copy()
    ob = bpy.data.objects.new(nombre, me)
    bpy.context.scene.collection.objects.link(ob)
    mundo = origen.matrix_world.copy()
    if padre is not None:
        ob.parent = padre
        ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_world = mundo
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    guardar = set(indices)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in guardar], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    return ob


def borrar_islas(obj, indices):
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    fuera = set(indices)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index in fuera], context="VERTS")
    bm.to_mesh(me)
    bm.free()


def caja_mundo(obj):
    """Caja de una malla en mundo (las 8 esquinas del bound_box no valen: la
    cadena de padres trae rotacion y hay que transformar los vertices)."""
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for v in obj.data.vertices:
        w = obj.matrix_world @ v.co
        for k in range(3):
            lo[k] = min(lo[k], w[k])
            hi[k] = max(hi[k], w[k])
    return lo, hi


def caja_de_todo():
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        a, b = caja_mundo(o)
        for k in range(3):
            lo[k] = min(lo[k], a[k])
            hi[k] = max(hi[k], b[k])
    return lo, hi


def rebasar_origen(obj, pivote):
    """Mueve el origen a `pivote` (mundo) sin mover la geometria.

    No vale transladar la malla por -pivote: los vertices viven en el espacio
    local, y la cadena de padres trae rotacion. El desplazamiento hay que
    llevarlo al espacio local con la parte 3x3 de la matriz de mundo.
    """
    mundo = obj.matrix_world.copy()
    desplazamiento = pivote - mundo.translation
    mundo.translation = pivote
    obj.matrix_world = mundo
    obj.data.transform(Matrix.Translation(-(mundo.to_3x3().inverted() @ desplazamiento)))


def anadir_barrel(nombre, padre):
    """Canon: recamara + tubo con anima, origen en la cara de culata."""
    culata_y = MUZZLE_Y - BARREL_LARGO
    recamara_y = culata_y + 0.205
    seg = 20
    verts = []
    caras = []

    def anillo(y, radio):
        base = len(verts)
        for i in range(seg):
            a = math.tau * i / seg
            verts.append(Vector((BORE_X + math.cos(a) * radio, y, BORE_Z + math.sin(a) * radio)))
        return base

    tubo_0 = anillo(recamara_y, BARREL_RADIO)
    tubo_1 = anillo(MUZZLE_Y, BARREL_RADIO)
    boca = anillo(MUZZLE_Y, PUNTA_RADIO)
    fondo = anillo(recamara_y + 0.02, PUNTA_RADIO)
    for i in range(seg):
        j = (i + 1) % seg
        caras.append([tubo_0 + i, tubo_0 + j, tubo_1 + j, tubo_1 + i])
        caras.append([tubo_1 + i, tubo_1 + j, boca + j, boca + i])
        caras.append([boca + i, boca + j, fondo + j, fondo + i])
    caras.append(list(range(fondo, fondo + seg))[::-1])

    ## Recamara: bloque con el lomo biselado y el teton de cierre debajo.
    cx, cz = BORE_X, BORE_Z
    hx, hz = 0.052, 0.058
    bloque = [
        Vector((cx - hx, culata_y, cz - hz)), Vector((cx + hx, culata_y, cz - hz)),
        Vector((cx + hx, culata_y, cz + hz)), Vector((cx - hx, culata_y, cz + hz)),
        Vector((cx - hx, recamara_y, cz - hz)), Vector((cx + hx, recamara_y, cz - hz)),
        Vector((cx + hx, recamara_y, cz + hz)), Vector((cx - hx, recamara_y, cz + hz)),
    ]
    base = len(verts)
    verts.extend(bloque)
    for cara in ([0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]):
        caras.append([base + i for i in cara])
    teton = [
        Vector((cx - hx * 0.7, recamara_y - 0.05, cz - hz - 0.035)), Vector((cx + hx * 0.7, recamara_y - 0.05, cz - hz - 0.035)),
        Vector((cx + hx * 0.7, recamara_y, cz - hz - 0.035)), Vector((cx - hx * 0.7, recamara_y, cz - hz - 0.035)),
        Vector((cx - hx * 0.7, recamara_y - 0.05, cz - hz)), Vector((cx + hx * 0.7, recamara_y - 0.05, cz - hz)),
        Vector((cx + hx * 0.7, recamara_y, cz - hz)), Vector((cx - hx * 0.7, recamara_y, cz - hz)),
    ]
    base = len(verts)
    verts.extend(teton)
    for cara in ([0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]):
        caras.append([base + i for i in cara])

    me = bpy.data.meshes.new(nombre)
    me.from_pydata([tuple(v) for v in verts], [], caras)
    me.validate()
    me.update()
    mat = bpy.data.materials.new("BarrelSteel")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.055, 0.057, 0.062, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.85
        bsdf.inputs["Roughness"].default_value = 0.31
    me.materials.append(mat)

    ob = bpy.data.objects.new(nombre, me)
    bpy.context.scene.collection.objects.link(ob)
    pivote = Vector((BORE_X, culata_y, BORE_Z))
    me.transform(Matrix.Translation(-pivote))
    if padre is not None:
        ob.parent = padre
        ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_world = Matrix.Translation(pivote)
    return ob, culata_y


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    antes = caja_de_todo()
    origen = bpy.data.objects.get(GRAB_BAG)
    if origen is None:
        raise SystemExit("el GLB no trae el nodo " + GRAB_BAG)
    slide = bpy.data.objects.get(SLIDE)
    mundo = origen.matrix_world.copy()
    islas = islas_de(origen.data, mundo)
    islas.sort(key=lambda i: -len(i["verts"]))

    ## Cuerpo del cargador: la isla que baja del brocal y sube hasta los labios.
    cuerpo = next(i for i in islas if i["lo"].z < -0.30 and i["hi"].z > 0.25)
    arbol = kdtree.KDTree(len(cuerpo["verts"]))
    for n, idx in enumerate(cuerpo["verts"]):
        arbol.insert(mundo @ origen.data.vertices[idx].co, n)
    arbol.balance()

    def toca_cargador(isla):
        for idx in isla["verts"]:
            _, _, dist = arbol.find(mundo @ origen.data.vertices[idx].co)
            if dist <= TOQUE:
                return True
        return False

    destino = {}
    for isla in islas:
        if isla["lo"].y > SPRING_BOX["y_min"] and isla["lo"].z >= SPRING_BOX["z"][0] and isla["hi"].z <= SPRING_BOX["z"][1]:
            destino[id(isla)] = "RecoilSpring"
        elif dentro(isla, TRIGGER_BOX):
            destino[id(isla)] = "Trigger"
        elif isla is cuerpo or (toca_cargador(isla) and isla["hi"].z <= TECHO_CARGADOR):
            destino[id(isla)] = "Magazine"
        else:
            destino[id(isla)] = "FrameDetail"

    grupos = {}
    for isla in islas:
        grupos.setdefault(destino[id(isla)], []).append(isla)
    print("=== ISLAS DEL NODO %s ===" % GRAB_BAG)
    for isla in islas:
        lo, hi = caja(isla)
        print("  %-12s %4d verts  y %.3f..%.3f  z %.3f..%.3f" % (
            destino[id(isla)], len(isla["verts"]), lo.y, hi.y, lo.z, hi.z))
    print("=== DESTINO ===", {k: sum(len(i["verts"]) for i in v) for k, v in grupos.items()})

    def verts_de(nombre):
        out = []
        for isla in grupos.get(nombre, []):
            out.extend(isla["verts"])
        return out

    ## Gatillo: el eje de giro esta donde el diente se agarra al armazon, o sea
    ## en su franja de arriba. Se mide sobre el DIENTE: la barra que va al
    ## fiador es larga y plana, y si entra en la media se lleva el pivote atras.
    gatillo_verts = verts_de("Trigger")
    pivote = Vector((0.0, 0.0, 0.0))
    if gatillo_verts:
        diente = []
        for isla in grupos.get("Trigger", []):
            if isla["lo"].z < 0.1:
                diente.extend(isla["verts"])
        puntos = [mundo @ origen.data.vertices[i].co for i in diente]
        tope = max(p.z for p in puntos)
        alto = [p for p in puntos if p.z > tope - 0.02]
        pivote = sum(alto, Vector((0.0, 0.0, 0.0))) / len(alto)

    padre = origen.parent
    if gatillo_verts:
        trigger = recortar(origen, gatillo_verts, "Trigger", padre)
        borrar_islas(origen, gatillo_verts)
        rebasar_origen(trigger, pivote)

    resorte_verts = verts_de("RecoilSpring")
    if resorte_verts:
        recortar(origen, resorte_verts, "RecoilSpring", slide)
        borrar_islas(origen, resorte_verts)

    herrajes = verts_de("FrameDetail")
    if herrajes:
        recortar(origen, herrajes, "FrameDetail", padre)
        borrar_islas(origen, herrajes)

    barrel, culata_y = anadir_barrel("Barrel", padre)
    bpy.context.view_layer.update()

    ## Invariante: partir el nodo no puede mover NADA. Si el arma cambia de
    ## sitio o de tamano, el error es de este script y hay que cortarlo aqui.
    despues = caja_de_todo()
    desvio = max((despues[0] - antes[0]).length, (despues[1] - antes[1]).length)
    print("CAJA antes min=%s max=%s" % (tuple(round(v, 4) for v in antes[0]), tuple(round(v, 4) for v in antes[1])))
    print("CAJA despues min=%s max=%s  desvio=%.5f u (%.2f mm)" % (
        tuple(round(v, 4) for v in despues[0]), tuple(round(v, 4) for v in despues[1]), desvio, desvio / MM))
    if desvio > 0.002:
        raise SystemExit("el arma se movio al partirla: revisa los transforms")

    print("GATILLO: pivote x=%.4f y=%.4f z=%.4f  verts=%d" % (pivote.x, pivote.y, pivote.z, len(gatillo_verts)))
    print("CANON: culata y=%.4f  boca y=%.4f  largo=%.1f mm  radio=%.1f mm" % (
        culata_y, MUZZLE_Y, BARREL_LARGO / MM, BARREL_RADIO / MM))

    bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_yup=True)
    print("EXPORTADO", DST)


main()
