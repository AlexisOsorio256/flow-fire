#!/usr/bin/env python3
"""ARMS: primera persona para el simulador de Glock 19 (donante BAMEN).

    blender --background --python tools/build_arms.py -- --out assets/models/fps_arms.glb --verify 1
    blender --background --python tools/build_arms.py -- --out /tmp/bamen_arms.glb --bind-only 1 --grip-report 1
    blender --background --python tools/build_arms.py -- --verify-only assets/models/fps_arms.glb

DONANTE  (NO esta en el repo: `downloads/` es gitignored)
---------------------------------------------------------
    downloads/models/bamen_fps_arms/scene.gltf
    BAMEN, "FREE [FPS Arms] GameReady - RIGGED"
    https://sketchfab.com/3d-models/free-fps-arms-gameready-rigged-296d30fc705b4dff85c2c8a2d2724e7f
    Licencia, textual del `license.txt` que viene en la descarga:
        license type:	CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
        requirements:	Author must be credited. Commercial use is allowed.
    CC-BY-4.0: atribucion OBLIGATORIA (la linea de credito exacta esta en
    `CREDITS_MODELS.md`), uso comercial permitido.
    Un checkout limpio tiene que bajar el ZIP de esa URL y descomprimirlo en
    `downloads/models/bamen_fps_arms/` (scene.gltf + scene.bin + textures/).

QUE HACE
--------
Coge el donante, tira la basura (la malla ajena `Icosphere` y los 10 huesos
hoja `*_end_*`, que no tienen pesos), lo normaliza a metros y lo AUTORA EN
ESPACIO DEL ARMA: el mismo sistema que `assets/models/g19_pistol.glb` (+Y
arriba, -Z al morro, origen en la raiz del arma). El puno derecho se coloca
sobre la empuñadura MIDIENDO el tunel del puño en la malla (no a ojo) y el
brazo sale de un IK analitico de dos huesos con pole. La POSE DE REPOSO del GLB
exportado es la de `Idle` en t=0, asi que el asset ya agarra la pistola aunque
nadie reproduzca un clip, y `GRIP_POS`/`GRIP_ROT` se quedan en (0,0,0).

DETALLE DEL DONANTE QUE HAY QUE CONOCER (medido, no supuesto)
------------------------------------------------------------
El glTF del donante NO es un rig "reposo = bind": sus 52 matrices inversas de
bind describen una T-pose mientras que los nodos describen una pose de brazos
en primera persona ya resuelta. Blender importa las dos cosas fielmente (bind
en la T-pose, `pose_bone.matrix` en la pose del autor), asi que el constructor
hace lo correcto: NORMALIZA a metros (la T-pose del bind vive a x100 del
origen), y REHORNEA el bind a la pose del autor antes de medir nada. A partir de
ahi el rig es un rig normal y metrico. Los huesos distales traen longitudes
falsas (p.ej. `Finger_4_3` = 1,58 m): la POSICION de las cabezas es la buena, y
la punta real de cada falange se mide en el hueso hoja `*_end_*` ANTES de
tirarlo (`TIP_LOCAL`). Ninguna medida de este archivo usa `pose_bone.tail`.

SALIDA
------
    assets/models/fps_arms.glb
    2 mallas skinned / 2 materiales / esqueleto deform-only de 42 huesos /
    5 clips exactos: Idle 3.00 s, Fire 0.26 s, Reload 2.10 s,
    ReloadEmpty 2.35 s, Inspect 2.00 s.  Nada mas.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

REPO = Path(__file__).resolve().parents[1]

DONOR = REPO / "downloads" / "models" / "bamen_fps_arms" / "scene.gltf"
GUN = REPO / "assets" / "models" / "g19_pistol.glb"
OUT = REPO / "assets" / "models" / "fps_arms.glb"

## Espacio del arma -> espacio de Blender: (x,y,z)_arma -> (x,-z,y)_blender.
GUN_TO_BLENDER = Matrix.Rotation(math.radians(90.0), 4, "X")

FPS = 100  # 100 fps: 0.26 / 1.02 / 1.40 / 1.72 / 2.35 s caen en frames enteros

FINGERS = ("f_index", "f_middle", "f_ring", "f_pinky")
FINGER_SRC = {"f_index": 2, "f_middle": 3, "f_ring": 4, "f_pinky": 5}

## ---------------------------------------------------------------------------
## MEDIDAS DEL ARMA (espacio del arma, metros), de `tools/_recon_grip.py` sobre
## NUESTRA g19_pistol.glb: no de la ficha del fabricante.
## ---------------------------------------------------------------------------
## Eje de la empuñadura (PCA del cuerpo del cargador, que es su canal interior)
## apuntando hacia ARRIBA.  Rake 17.6 grados.
GRIP_AXIS = Vector((-0.0041, 0.9529, -0.3032)).normalized()
## Centro del tunel del puño: punto medio de la empuñadura.
GRIP_CENTER = Vector((0.0, -0.0425, 0.0390))
## Desplazamiento y giro del puño sobre la empuñadura: los AJUSTA `fit_grip`
## midiendo el contacto dedo-empuñadura, no son numeros a ojo.
GRIP_OFFSET = Vector((0.0, 0.0, 0.0))
GRIP_ROLL = 0.0
## Normal palmar (sale de la piel de la palma).  El eje del tunel del puño es la
## LINEA DE NUDILLOS (meñique -> indice), no el eje del antebrazo: al cerrar el
## puño el unico cilindro que entra en el hueco va de nudillo a nudillo.  Con el
## indice arriba y la empuñadura vertical, la palma queda envolviendo el costado
## DERECHO de la empuñadura y mira hacia dentro-atras (izquierda y algo al
## morro); asi la muñeca cae detras del arma y el pulgar cruza al lado izquierdo.
GRIP_PALM = {"R": Vector((-0.85, 0.0, -0.53)).normalized(),
             "L": Vector((0.85, 0.0, -0.53)).normalized()}

## Corredera (cara trasera y cara superior medidas) y su recorrido.
SLIDE_REAR_Z = 0.0803
SLIDE_TOP_Y = 0.0634
SLIDE_TRAVEL = 0.039
## Boton del reten del cargador: vertice mas a la izquierda del armazon.
MAG_RELEASE = Vector((-0.0130, -0.0182, 0.0322))

## Cabeza del humero (hombro) en espacio del arma.  La derecha cae detras del
## plano de la camara en el encuadre de cadera, que es lo que deja el antebrazo
## saliendo por abajo en vez de cruzar el arma.  Estos tres pares los AJUSTA el
## banco mirando el encuadre real de `frame.json`, no son constantes del donante.
SHOULDER_R = Vector((0.130, -0.100, 0.440))
SHOULDER_L = Vector((-0.150, -0.230, 0.310))
POLE_R = Vector((0.22, -0.90, 0.36))
POLE_L = Vector((-0.30, -0.88, 0.36))
## Longitudes reales del donante (medidas de sus cabezas, no de la ficha).
UP_LEN = 0.3469
FORE_LEN = 0.2463

## ---------------------------------------------------------------------------
## FLEXION DE DEDOS (grados, positivo = hacia la palma).  Son DELTAS respecto de
## la pose de reposo del DONANTE (que ya trae los dedos medio cerrados): el
## signo real de cada falange se MIDE en la malla (ver `measure_curl_signs`) y el
## EJE de flexion se mide de la geometria (ver `measure_flex_axes`), no se
## supone que sea la X local.
## ---------------------------------------------------------------------------
CURL = {
    "grip": {"f_index": (2, -4, -6), "f_middle": (30, 38, 26),
             "f_ring": (32, 40, 28), "f_pinky": (34, 42, 30)},
    "relax": {"f_index": (2, 2, 2), "f_middle": (4, 5, 4),
              "f_ring": (5, 6, 5), "f_pinky": (6, 7, 6)},
    "open": {"f_index": (-14, -18, -12), "f_middle": (-16, -20, -14),
             "f_ring": (-16, -20, -14), "f_pinky": (-18, -22, -16)},
    "slide": {"f_index": (6, 6, 6), "f_middle": (10, 12, 10),
              "f_ring": (11, 13, 11), "f_pinky": (12, 14, 12)},
    "mag": {"f_index": (24, 30, 20), "f_middle": (28, 34, 24),
            "f_ring": (30, 36, 26), "f_pinky": (32, 38, 28)},
    "point": {"f_index": (-8, -12, -8), "f_middle": (20, 26, 18),
              "f_ring": (22, 28, 20), "f_pinky": (24, 30, 22)},
    "light": {"f_index": (2, 2, 2), "f_middle": (4, 5, 4),
              "f_ring": (5, 6, 5), "f_pinky": (6, 7, 6)},
}
## Pulgar: 4 falanges en este donante.  Flexion + oposicion (swing).
THUMB = {
    "grip": (6, 8, 8, 6),
    "relax": (2, 2, 2, 2),
    "open": (-6, -6, -6, -6),
    "slide": (4, 5, 5, 4),
    "mag": (6, 8, 8, 6),
    "point": (6, 8, 8, 6),
    "light": (2, 2, 2, 2),
}
THUMB_SWING = {
    "grip": (-10.0, 0.0, 0.0, 0.0),
    "relax": (0.0, 0.0, 0.0, 0.0),
    "open": (0.0, 0.0, 0.0, 0.0),
    "slide": (-6.0, 0.0, 0.0, 0.0),
    "mag": (-8.0, 0.0, 0.0, 0.0),
    "point": (-8.0, 0.0, 0.0, 0.0),
    "light": (0.0, 0.0, 0.0, 0.0),
}
REST_CURL = {"R": "grip", "L": "relax"}

NVEC = 4 * 3 + 4 + 4  # 4 dedos x 3 falanges + pulgar 4 + swing 4
ZERO_VEC = (0.0,) * NVEC

## Rellenado por `measure_flex_axes` / `measure_tips` en tiempo de construccion.
FLEX_AXIS: dict = {}
FLEX_SWING: dict = {}
TIP_LOCAL: dict = {}
SIGNS: dict = {}


# ===========================================================================
# utilidades de escena
# ===========================================================================
def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for group in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
                  bpy.data.armatures, bpy.data.actions, bpy.data.images,
                  bpy.data.cameras, bpy.data.lights, bpy.data.collections):
        for item in list(group):
            if item.users == 0:
                group.remove(item)
    ## EL FPS DE LA ESCENA ES PARTE DEL CONTRATO, no un detalle.
    ## El exportador glTF convierte FRAMES a SEGUNDOS con `scene.render.fps`, no
    ## con el fps con el que se keyframearon las acciones. Con el valor por
    ## defecto de Blender (24) los cinco clips salian 100/24 = 4,17 veces mas
    ## largos (Idle 12,50 s en vez de 3,00) y los brazos se desincronizaban por
    ## completo de la mecanica. Lo caza `tools/check_weapon.tscn`.
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0


def import_gltf(path: Path) -> list:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return [o for o in bpy.data.objects if o not in before]


def activate(obj) -> None:
    for o in list(bpy.context.selected_objects):
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def update() -> None:
    bpy.context.view_layer.update()


## Espacio del arma -> espacio de Blender.  El constructor razona TODO en espacio
## del arma (+Y arriba, -Z al morro) y convierte en el ultimo momento, al
## escribir huesos y malla: (x,y,z)_arma -> (x,-z,y)_blender.  El exportador glTF
## deshace justo esa conversion, asi que el GLB sale en espacio del arma con el
## nodo raiz en IDENTIDAD (que es lo que exige el contrato: GRIP_POS/GRIP_ROT en
## cero y el brazo colgando de BodyGive sin transformacion).
def b_point(v) -> Vector:
    return GUN_TO_BLENDER @ Vector(v)


def b_mat(m: Matrix) -> Matrix:
    return GUN_TO_BLENDER @ m


# ===========================================================================
# matrices
# ===========================================================================
def frame_matrix(origin: Vector, ydir: Vector, zref: Vector) -> Matrix:
    """Base ortonormal derecha con Y = ydir y Z lo mas cerca posible de zref.

    Se usa para TODO: huesos (Y = hueso) y bocas de agarre (Y = eje del tunel
    del puño, Z = normal palmar).  La misma construccion en los dos sitios, o el
    mapeo puño -> empuñadura no cuadra.
    """
    Y = Vector(ydir).normalized()
    Z = Vector(zref)
    Z = Z - Y * Z.dot(Y)
    if Z.length < 1e-9:
        Z = Vector((0.0, 0.0, 1.0)) - Y * Y.z
        if Z.length < 1e-9:
            Z = Vector((1.0, 0.0, 0.0)) - Y * Y.x
    Z.normalize()
    X = Y.cross(Z)
    return Matrix(((X.x, Y.x, Z.x, origin.x),
                   (X.y, Y.y, Z.y, origin.y),
                   (X.z, Y.z, Z.z, origin.z),
                   (0.0, 0.0, 0.0, 1.0)))


def grip_socket(side: str, slide: float = 0.0, roll_deg: float = 0.0,
                offset: Vector | None = None) -> Matrix:
    """Boca del agarre de la empuñadura en espacio del arma."""
    o = (GRIP_CENTER + GRIP_OFFSET + GRIP_AXIS * slide
         + (Vector(offset) if offset is not None else Vector()))
    m = frame_matrix(o, GRIP_AXIS, GRIP_PALM[side])
    roll = roll_deg + GRIP_ROLL
    if abs(roll) > 1e-9:
        m = m @ Matrix.Rotation(math.radians(roll), 4, "Y")
    return m


def mag_socket(offset: float) -> Matrix:
    """Boca del puño izquierdo agarrando el cargador `offset` metros por debajo
    del brocal (MAGAZINE_OUT_AXIS = -Y del arma, constante de GlockWeapon.gd)."""
    m = grip_socket("L")
    m.translation = m.translation + Vector((0.0, -offset, 0.0))
    return m


def slide_socket(travel: float, lift: float = 0.0) -> Matrix:
    """Puño izquierdo agarrando la corredera por detras, con los dedos por
    encima: el eje del tunel es el del cañon (+Z, hacia el tirador) y la palma
    mira a la derecha (+X).  `travel` es lo que ha retrocedido la corredera."""
    z = SLIDE_REAR_Z + travel - 0.017
    o = Vector((0.0, SLIDE_TOP_Y - 0.014 + lift, z))
    ## Tunel hacia el MORRO (indice delante, meñique detras) y palma a la
    ## derecha (la palma apoya en el costado izquierdo de la corredera).
    return frame_matrix(o, Vector((0.0, 0.0, -1.0)), Vector((1.0, 0.0, 0.0)))


def socket_from_dir(origin: Vector, hand_dir: Vector, palm_hint: Vector,
                    d_local: Vector) -> Matrix:
    """Boca a partir de la direccion que debe tomar el hueso `hand` (su Y) y una
    pista de normal palmar.  Es la forma natural de colocar la mano cuando NO
    agarra nada (reposo, transiciones): se dice hacia donde apunta la mano."""
    Yw = Vector(hand_dir).normalized()
    Zw = Vector(palm_hint)
    Zw = (Zw - Yw * Zw.dot(Yw)).normalized()
    Xw = Yw.cross(Zw)
    Bw = Matrix(((Xw.x, Yw.x, Zw.x, 0.0), (Xw.y, Yw.y, Zw.y, 0.0),
                 (Xw.z, Yw.z, Zw.z, 0.0), (0.0, 0.0, 0.0, 1.0)))
    Yl = Vector(d_local).normalized()
    Zl = Vector((0.0, 0.0, 1.0))
    Zl = (Zl - Yl * Zl.dot(Yl)).normalized()
    Xl = Yl.cross(Zl)
    Bl = Matrix(((Xl.x, Yl.x, Zl.x, 0.0), (Xl.y, Yl.y, Zl.y, 0.0),
                 (Xl.z, Yl.z, Zl.z, 0.0), (0.0, 0.0, 0.0, 1.0)))
    R = Bw @ Bl.inverted()
    m = R.to_4x4()
    m.translation = Vector(origin)
    return m


def blend_matrix(a: Matrix, b: Matrix, k: float) -> Matrix:
    ta, ra, _ = a.decompose()
    tb, rb, _ = b.decompose()
    return Matrix.LocRotScale(ta.lerp(tb, k), ra.slerp(rb, k), Vector((1.0, 1.0, 1.0)))


def solve_elbow(S: Vector, W: Vector, l1: float, l2: float, pole: Vector) -> Vector:
    """IK analitico de dos huesos: posicion del codo."""
    d = W - S
    dist = d.length
    if dist < 1e-6:
        d = Vector((0.0, -1.0, 0.0))
        dist = 1e-6
    dist = min(dist, (l1 + l2) * 0.999)
    n = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    p = Vector(pole)
    p = p - n * p.dot(n)
    if p.length < 1e-6:
        p = Vector((0.0, -1.0, 0.0)) - n * Vector((0.0, -1.0, 0.0)).dot(n)
    p.normalize()
    return S + n * a + p * h


# ===========================================================================
# nombres del donante -> nombres canonicos
# ===========================================================================
def canonical(name: str) -> str | None:
    """Nombre canonico de un hueso del donante, o None si hay que tirarlo."""
    if name == "_rootJoint":
        return "root"
    if name.startswith("FPS Arms Root"):
        return "chest"
    m = re.match(r"^Arm_([12])\.([LR])_\d+$", name)
    if m:
        return ("upper_arm." if m.group(1) == "1" else "forearm.") + m.group(2)
    m = re.match(r"^Hand_([12])\.([LR])_\d+$", name)
    if m:
        return ("hand." if m.group(1) == "1" else "palm.") + m.group(2)
    m = re.match(r"^Finger_([1-5])_(\d)\.([LR])_\d+$", name)
    if m:
        which, phalanx, side = int(m.group(1)), int(m.group(2)), m.group(3)
        if which == 1:
            return "thumb.%02d.%s" % (phalanx, side)
        finger = {2: "f_index", 3: "f_middle", 4: "f_ring", 5: "f_pinky"}[which]
        return "%s.%02d.%s" % (finger, phalanx, side)
    return None


def strip_donor(arm, meshes: list, world: Matrix) -> None:
    """Tira todo lo que no sea la armadura o las dos mallas del donante.

    `world` es la matriz de mundo que tenia la armadura ANTES de soltar los
    empties de Sketchfab: borrar un padre en Blender reescribe el
    `matrix_world` del hijo, asi que hay que reponerla a mano."""
    keep = {arm, *meshes}
    for obj in list(bpy.data.objects):
        if obj not in keep:
            print("BUILD fuera objeto ajeno:", obj.name, obj.type)
            bpy.data.objects.remove(obj, do_unlink=True)
    ## Las mallas siguen colgando de la armadura (eso es lo que empareja piel y
    ## esqueleto al exportar); solo la armadura pierde a sus padres.
    arm.parent = None
    arm.matrix_world = world.copy()
    arm.matrix_parent_inverse = Matrix.Identity(4)
    for mesh in meshes:
        mesh.parent = arm
        mesh.matrix_parent_inverse = Matrix.Identity(4)
    update()


def measure_tips(arm) -> dict:
    """Offset LOCAL de la punta real de cada falange distal, medido del hueso
    hoja `*_end_*` (que se tira despues).

    Se mide en la POSE, no en el bind: en el bind del donante los diez huesos
    hoja caen todos en el MISMO punto degenerado, a 1,57 m de su padre, y de ahi
    solo sale basura.  En la pose del autor cada hoja esta a ~2 cm de su padre,
    que es la falange distal.  El offset es local al hueso, asi que sobrevive al
    rehorneado del bind."""
    tips = {}
    for b in arm.data.bones:
        if "_end_" not in b.name:
            continue
        parent = b.parent
        if parent is None:
            continue
        local = (arm.pose.bones[parent.name].matrix.inverted()
                 @ arm.pose.bones[b.name].head)
        tips[parent.name] = local
        print("BUILD punta %-24s offset local=(%.4f,%.4f,%.4f) |d|=%.4f"
              % (parent.name, local.x, local.y, local.z, local.length))
    return tips


def strip_leaves(arm) -> list:
    """Quita los huesos hoja `*_end_*` (glTF leaf bones, sin pesos)."""
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm.data.edit_bones
    gone = []
    for name in [n for n in ebs.keys() if "_end_" in n]:
        eb = ebs[name]
        kids = [c.name for c in eb.children]
        assert not kids, "BUILD ABORTA: %s tiene hijos %s" % (name, kids)
        assert len(arm.pose.bones[name].constraints) == 0, \
            "BUILD ABORTA: %s tiene constraints" % name
        ebs.remove(eb)
        gone.append(name)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("BUILD fuera %d huesos hoja (_end)" % len(gone))
    return gone


def rename_bones(arm, meshes: list) -> None:
    """Renombra huesos y grupos de vertices a los nombres canonicos."""
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm.data.edit_bones
    mapping = {}
    for name in list(ebs.keys()):
        new = canonical(name)
        assert new is not None, "BUILD ABORTA: hueso sin nombre canonico %s" % name
        mapping[name] = new
    for old, new in mapping.items():
        if old != new:
            ebs[old].name = new
    bpy.ops.object.mode_set(mode="OBJECT")
    for mesh in meshes:
        for vg in mesh.vertex_groups:
            if vg.name in mapping:
                vg.name = mapping[vg.name]
    for mesh in meshes:
        for vg in list(mesh.vertex_groups):
            if vg.name not in mapping.values():
                print("BUILD fuera grupo de vertices:", vg.name)
                mesh.vertex_groups.remove(vg)
    n = len(arm.data.bones)
    deform = sum(1 for b in arm.data.bones if b.use_deform)
    print("BUILD huesos: %d (deform %d)" % (n, deform))


def normalize_world(arm, meshes: list, W: Matrix) -> None:
    """Deja la armadura y las mallas en IDENTIDAD y su espacio en espacio-mundo.

    El importador glTF mete el asset girado (Y-arriba -> Z-arriba) y con la
    cadena de empties de Sketchfab.  Todo el constructor razona en
    `GUN_TO_BLENDER @ espacio_del_arma` == espacio-mundo de Blender, asi que hay
    que hornear esa transformacion en los huesos y en la malla y soltar los
    empties: si no, el nodo raiz del GLB sale con rotacion y escala.
    """
    if max(abs(W[i][j] - Matrix.Identity(4)[i][j]) for i in range(4) for j in range(4)) < 1e-9:
        print("BUILD normalizacion: la armadura ya estaba en identidad")
        return
    for mesh in meshes:
        flat = []
        for v in mesh.data.vertices:
            w = W @ v.co
            flat += [w.x, w.y, w.z]
        mesh.data.vertices.foreach_set("co", flat)
        mesh.data.update()
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm.data.edit_bones
    heads = {n: ebs[n].head.copy() for n in ebs.keys()}
    tails = {n: ebs[n].tail.copy() for n in ebs.keys()}
    zaxes = {n: ebs[n].z_axis.copy() for n in ebs.keys()}
    for n in heads:
        ebs[n].head = W @ heads[n]
        ebs[n].tail = W @ tails[n]
        ebs[n].align_roll(W.to_3x3() @ zaxes[n])
    bpy.ops.object.mode_set(mode="OBJECT")
    for mesh in meshes:
        ## La malla tiene que seguir COLGANDO de la armadura: el exportador glTF
        ## empareja piel y esqueleto por la jerarquia (si no, avisa "Armature
        ## must be the parent of skinned mesh" y la piel sale por el nombre).
        mesh.parent = arm
        mesh.matrix_parent_inverse = Matrix.Identity(4)
        mesh.matrix_basis = Matrix.Identity(4)
    arm.parent = None
    arm.matrix_basis = Matrix.Identity(4)
    arm.matrix_parent_inverse = Matrix.Identity(4)
    update()
    print("BUILD normalizacion: armadura y mallas en identidad (mundo = espacio del arma)")


def drop_extra_uvs(meshes: list) -> None:
    """El donante trae 3 juegos de UV y el material solo usa el primero: los
    otros dos solo engordan el GLB."""
    for mesh in meshes:
        while len(mesh.data.uv_layers) > 1:
            n = mesh.data.uv_layers[-1].name
            mesh.data.uv_layers.remove(mesh.data.uv_layers[-1])
            print("BUILD fuera capa UV:", n)


# ===========================================================================
# medida del contacto mano-empuñadura
# ===========================================================================
def skinned_positions(arm, mesh, base: dict) -> list:
    """Posiciones de los vertices con la POSE ACTUAL (mismo calculo que el bake).
    Hace falta para poder medir el puño cerrado antes de hornear nada."""
    vgs = [vg.name for vg in mesh.vertex_groups]
    out = []
    for v in mesh.data.vertices:
        acc = Vector()
        tot = 0.0
        for g in v.groups:
            pb = arm.pose.bones.get(vgs[g.group])
            if pb is None or g.weight <= 0.0:
                continue
            acc += (pb.matrix @ base[vgs[g.group]].inverted() @ v.co) * g.weight
            tot += g.weight
        out.append(acc / tot if tot > 1e-9 else v.co.copy())
    return out


def gun_grip_bvh() -> BVHTree:
    """Arbol BVH con la superficie REAL de la empuñadura (armazon, cargador y
    gatillo) en espacio del arma.  Se importa el arma solo para medirla y se
    borra acto seguido: el brazo no puede depender de que el arma este en la
    escena al exportar.

    Medir contra la superficie y no contra una caja es lo que permite pedir
    contacto de verdad: la empuñadura es asimetrica (la culata del cargador vuela
    hacia atras abajo) y una caja simetrica empujaba las yemas 12 mm fuera."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(GUN))
    new = [o for o in bpy.data.objects if o not in before]
    back = GUN_TO_BLENDER.inverted()
    verts = []
    polys = []
    for o in new:
        if o.type != "MESH" or o.name not in ("Frame", "Magazine", "Trigger"):
            continue
        base = len(verts)
        for v in o.data.vertices:
            verts.append(back @ (o.matrix_world @ v.co))
        for poly in o.data.polygons:
            polys.append([base + i for i in poly.vertices])
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    if not polys:
        raise SystemExit("BUILD ABORTA: no se pudo leer la superficie de %s" % GUN)
    print("BUILD superficie del arma: %d verts / %d caras" % (len(verts), len(polys)))
    return BVHTree.FromPolygons(verts, polys)


def inside_gun(bvh: BVHTree, p: Vector) -> bool:
    """Dentro/fuera por PARIDAD DE CRUCES de un rayo.

    El signo por normal de la cara falla en una malla de juego con normales
    dudosas: daba -21 mm para un punto que esta 16 mm POR DEBAJO del arma."""
    direction = Vector((1.0, 0.0, 0.0))
    origin = p.copy()
    hits = 0
    for _ in range(12):
        loc, nor, idx, dist = bvh.ray_cast(origin, direction)
        if loc is None:
            break
        hits += 1
        origin = loc + direction * 1e-5
    return (hits % 2) == 1


def surf_gap(bvh: BVHTree, p: Vector) -> float:
    """Distancia CON SIGNO a la superficie del arma: >0 aire, <0 dentro.

    El test de paridad es caro y solo puede dar "dentro" cerca de la superficie:
    fuera de 2 mm, si el punto cae del lado de la normal de la cara mas cercana,
    ya se sabe que esta fuera sin lanzar un rayo.  El atajo es SEGURO: con una
    normal invertida el producto punto sale negativo y se cae al test de paridad
    de siempre, nunca al reves."""
    hit = bvh.find_nearest(p)
    if hit is None or hit[0] is None:
        return 9.9
    off = p - hit[0]
    d = off.length
    if d > 0.002 and hit[1] is not None and off.dot(hit[1]) > 0.0:
        return d
    return -d if inside_gun(bvh, p) else d


def pad_points(arm, meshes: list, base: dict, side: str, f_arm: Matrix,
               only: tuple | None = None) -> dict:
    """Puntos de la malla que forman cada yema (y la palma), en el marco de la
    boca de referencia.  Es la materia que tiene que TOCAR la empuñadura.

    `only` limita las etiquetas que se devuelven: el refinado por dedo no
    necesita recorrer las cinco."""
    inv = f_arm.inverted()
    groups = {}
    for f in FINGERS:
        for b in ("02", "03"):
            groups["%s.%s.%s" % (f, b, side)] = f
    for b in thumb_bones(side):
        groups[b] = "thumb"
    groups["hand.%s" % side] = "palm"
    groups["palm.%s" % side] = "palm"
    if only is not None:
        groups = {k: v for k, v in groups.items() if v in only}
    out: dict = {k: [] for k in only} if only is not None else {}
    for mesh in meshes:
        idx2name = {g.index: g.name for g in mesh.vertex_groups}
        world = skinned_positions(arm, mesh, base)
        for v, p in zip(mesh.data.vertices, world):
            if not v.groups:
                continue
            g = max(v.groups, key=lambda x: x.weight)
            if g.weight < 0.5:
                continue
            tag = groups.get(idx2name.get(g.group))
            if tag is None:
                continue
            out.setdefault(tag, []).append(inv @ p)
    return out


# ===========================================================================
# flexion de dedos
# ===========================================================================
def finger_bones(side: str, finger: str) -> list:
    return ["%s.%02d.%s" % (finger, i, side) for i in (1, 2, 3)]


def thumb_bones(side: str) -> list:
    return ["thumb.%02d.%s" % (i, side) for i in (1, 2, 3, 4)]


def finger_joints(arm, side: str, finger: str) -> list:
    """Cuatro puntos del dedo: las tres CABEZAS mas la punta real.

    La punta NO es `pose_bone.tail` (las longitudes distales del donante son
    falsas): es el offset local que se midio del hueso hoja antes de tirarlo."""
    chain = finger_bones(side, finger)
    pts = [arm.pose.bones[n].head.copy() for n in chain]
    pts.append(arm.pose.bones[chain[-1]].matrix @ TIP_LOCAL[chain[-1]])
    return pts


def thumb_joints(arm, side: str) -> list:
    chain = thumb_bones(side)
    pts = [arm.pose.bones[n].head.copy() for n in chain]
    pts.append(arm.pose.bones[chain[-1]].matrix @ TIP_LOCAL[chain[-1]])
    return pts


def curl_vec(preset: str) -> tuple:
    v = []
    for f in FINGERS:
        v += list(CURL[preset][f])
    v += list(THUMB[preset]) + list(THUMB_SWING[preset])
    return tuple(float(x) for x in v)


def lerp_vec(a, b, k):
    return tuple(x + (y - x) * k for x, y in zip(a, b))


def vec_with(base: tuple, overrides: dict) -> tuple:
    """Copia de `base` con algunos canales cambiados (por ejemplo el indice
    extendido para pulsar el reten)."""
    v = list(base)
    for key, val in overrides.items():
        if key == "f_index":
            v[0:3] = list(val)
        elif key == "f_middle":
            v[3:6] = list(val)
        elif key == "f_ring":
            v[6:9] = list(val)
        elif key == "f_pinky":
            v[9:12] = list(val)
        elif key == "thumb":
            v[12:16] = list(val)
        elif key == "swing":
            v[16:20] = list(val)
    return tuple(v)


def palm_normal(arm, side: str) -> Vector:
    """Normal palmar (sale de la palma) a partir de la QUIRALIDAD de la mano:
    Y_mano x (indice -> meñique), con el signo del lado.  No se mide con el
    desplazamiento de las puntas: con el puño cerrado la punta vuelve hacia la
    muñeca y esa direccion deja de ser la normal palmar."""
    hand = arm.pose.bones["hand.%s" % side]
    ydir = (hand.matrix.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized()
    idx = arm.pose.bones["f_index.01.%s" % side].head.copy()
    pnk = arm.pose.bones["f_pinky.01.%s" % side].head.copy()
    n = ydir.cross(pnk - idx).normalized()
    return n if side == "R" else -n


def measure_flex_axes(arm) -> None:
    """EJE de flexion de cada falange, MEDIDO de la geometria de la pose.

    El plano en que se dobla un dedo lo define el producto vectorial de dos
    falanges consecutivas; ese vector, llevado al espacio LOCAL del hueso, es el
    eje sobre el que hay que rotar.  Suponer "la X local" funciona en algunos
    rigs y en otros dobla el dedo de lado; medirlo no supone nada."""
    for side in ("R", "L"):
        for f in FINGERS:
            pts = finger_joints(arm, side, f)
            n = (pts[1] - pts[0]).cross(pts[2] - pts[1])
            if n.length < 1e-9:
                n = (pts[2] - pts[0]).cross(pts[3] - pts[1])
            n.normalize()
            for name in finger_bones(side, f):
                pb = arm.pose.bones[name]
                ax = (pb.matrix.to_3x3().inverted() @ n).normalized()
                FLEX_AXIS[name] = ax
                FLEX_SWING[name] = ax.cross(Vector((0.0, 1.0, 0.0))).normalized()
        pts = thumb_joints(arm, side)
        n = (pts[1] - pts[0]).cross(pts[2] - pts[1])
        if n.length < 1e-9:
            n = (pts[2] - pts[0]).cross(pts[3] - pts[1])
        n.normalize()
        for name in thumb_bones(side):
            pb = arm.pose.bones[name]
            ax = (pb.matrix.to_3x3().inverted() @ n).normalized()
            FLEX_AXIS[name] = ax
            FLEX_SWING[name] = ax.cross(Vector((0.0, 1.0, 0.0))).normalized()
    print("BUILD ejes de flexion medidos en %d falanges" % len(FLEX_AXIS))


def measure_curl_signs(arm, meshes: list, side: str) -> dict:
    """Signo de la flexion de cada falange: positivo = hacia la palma.

    Se decide con la MALLA, no con una suposicion: se aplica una flexion ligera
    con los dos signos y se mira cual acerca las puntas a la superficie de la
    palma."""
    names = {"hand.%s" % side, "palm.%s" % side}
    palm_pts = []
    for mesh in meshes:
        idx2name = {g.index: g.name for g in mesh.vertex_groups}
        mesh_w = mesh.matrix_world
        for v in mesh.data.vertices:
            if not v.groups:
                continue
            g = max(v.groups, key=lambda x: x.weight)
            if idx2name.get(g.group) in names and g.weight > 0.5:
                palm_pts.append(mesh_w @ v.co)
    best = 1.0
    best_d = None
    for s in (1.0, -1.0):
        clear_fingers(arm, side)
        update()
        v = list(ZERO_VEC)
        for f in FINGERS:
            v[FINGERS.index(f) * 3:FINGERS.index(f) * 3 + 3] = list(CURL["light"][f])
        v[12:16] = list(THUMB["light"])
        for name, q in finger_rots(side, tuple(v), ZERO_VEC, {n: s for n in FLEX_AXIS
                                                              if n.endswith("." + side)}).items():
            pb = arm.pose.bones.get(name)
            if pb is not None:
                pb.rotation_mode = "QUATERNION"
                pb.rotation_quaternion = q
        update()
        tot = 0.0
        for f in FINGERS:
            tip = finger_joints(arm, side, f)[-1]
            tot += min((tip - p).length for p in palm_pts)
        tip = thumb_joints(arm, side)[-1]
        tot += min((tip - p).length for p in palm_pts)
        print("BUILD signo %s: s=%+d distancia punta-palma=%.4f" % (side, int(s), tot))
        if best_d is None or tot < best_d:
            best_d = tot
            best = s
    clear_fingers(arm, side)
    update()
    print("BUILD signo %s elegido: %+d (%.4f m)" % (side, int(best), best_d))
    return {n: best for n in FLEX_AXIS if n.endswith("." + side)}


def finger_rots(side: str, vec: tuple, rest: tuple, signs: dict) -> dict:
    """Rotacion local (quaternion) de cada falange para la flexion ABSOLUTA `vec`
    medida desde la flexion `rest`.  Lo usan por igual los clips (que la escriben
    como `matrix_basis`) y el bind (que la hornea en la pose de reposo)."""
    out = {}
    i = 0
    for f in FINGERS:
        for j, name in enumerate(finger_bones(side, f)):
            ang = math.radians(vec[i + j] - rest[i + j]) * signs.get(name, 1.0)
            out[name] = Quaternion(FLEX_AXIS[name], ang)
        i += 3
    for j, name in enumerate(thumb_bones(side)):
        ang = math.radians(vec[12 + j] - rest[12 + j]) * signs.get(name, 1.0)
        q = Quaternion(FLEX_AXIS[name], ang)
        sw = math.radians(vec[16 + j] - rest[16 + j])
        if abs(sw) > 1e-9:
            q = Quaternion(FLEX_SWING[name], sw) @ q
        out[name] = q
    return out


def apply_fingers(arm, side: str, vec: tuple, signs: dict, rest: tuple) -> None:
    """Escribe la flexion ABSOLUTA `vec` como delta respecto de la del bind."""
    for name, q in finger_rots(side, vec, rest, signs).items():
        pb = arm.pose.bones.get(name)
        if pb is not None:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q


def clear_fingers(arm, side: str) -> None:
    for name in list(FLEX_AXIS):
        if not name.endswith("." + side):
            continue
        pb = arm.pose.bones.get(name)
        if pb:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion()


# ===========================================================================
# medida de la boca del puño
# ===========================================================================
def measure_socket(arm, side: str, preset: str, signs: dict) -> tuple:
    """Atajo por nombre de preset (el vector se congela tras el ajuste)."""
    out = measure_socket_vec(arm, side, curl_vec(preset), signs)
    clear_fingers(arm, side)
    update()
    return out


def measure_socket_vec(arm, side: str, vec: tuple, signs: dict) -> tuple:
    """Mide EN LA MALLA un marco rigido del puño: centro del tunel, eje del
    tunel (normal del plano de flexion de los cuatro dedos) y normal palmar
    (direccion en la que se mueven las puntas al cerrar).  Devuelve el marco en
    el espacio LOCAL del hueso `hand.<side>` (que no se mueve: solo se cierran
    los dedos) mas la direccion del hueso `hand` dentro de esa boca.

    El marco local es INVARIANTE al cambio de pose de reposo, que es justo lo
    que hace falta cuando el bind se reescribe."""
    clear_fingers(arm, side)
    update()
    palm = palm_normal(arm, side)

    apply_fingers(arm, side, vec, signs, ZERO_VEC)
    update()

    joints = []
    normals = []
    for f in FINGERS:
        pts = finger_joints(arm, side, f)
        joints += pts
        n = (pts[1] - pts[0]).cross(pts[2] - pts[1])
        if n.length < 1e-9:
            n = (pts[2] - pts[0]).cross(pts[3] - pts[1])
        if n.length > 1e-9:
            normals.append(n.normalized())
    axis = Vector()
    for n in normals:
        if n.dot(normals[0]) < 0.0:
            n = -n
        axis += n
    axis.normalize()

    center = sum(joints, Vector()) / len(joints)

    hand = arm.pose.bones["hand.%s" % side]
    ## Signo del eje: el tunel va del MEÑIQUE al INDICE, asi con la empuñadura
    ## vertical el indice queda arriba (que es como se agarra una pistola).
    ref = (arm.pose.bones["f_index.01.%s" % side].head
           - arm.pose.bones["f_pinky.01.%s" % side].head)
    if axis.dot(ref) < 0.0:
        axis = -axis
    f_arm = frame_matrix(center, axis, palm)
    f_local = hand.matrix.inverted() @ f_arm
    d_local = (f_arm.to_3x3().inverted() @ (hand.matrix.to_3x3()
               @ Vector((0.0, 1.0, 0.0)))).normalized()
    print("BUILD boca %s: tunel=(%.4f,%.4f,%.4f) eje=(%.3f,%.3f,%.3f) palma=(%.3f,%.3f,%.3f)"
          % (side, center.x, center.y, center.z, axis.x, axis.y, axis.z,
             palm.x, palm.y, palm.z))
    print("      radio del tunel=%.4f m | mano Y en la boca=(%.3f,%.3f,%.3f)" % (
        max((p - center - axis * (p - center).dot(axis)).length for p in joints),
        d_local.x, d_local.y, d_local.z))
    ## NO se abre la mano aqui: el que mide la malla necesita el puño cerrado.
    return f_local, d_local, f_arm


# ===========================================================================
# pose
# ===========================================================================
def scale_curl(vec: tuple, scale: float, pinky_extra: float = 0.0) -> tuple:
    """Escala la flexion de medio/anular/meñique y añade un extra al meñique (es
    el dedo corto: con la misma flexion que el anular no llega a la cara
    delantera).  El indice se queda extendido a lo largo del armazon, que es lo
    que hace que los dedos se lean separados, y el pulgar no se toca."""
    v = list(vec)
    for i in range(3, 12):
        v[i] = v[i] * scale
    for i in range(9, 12):
        v[i] = v[i] + pinky_extra
    return tuple(v)


def grip_report(arm, meshes: list, base: dict, side: str, signs: dict, bvh: BVHTree) -> None:
    """Informe POR DEDO del contacto con la empuñadura, medido sobre la malla ya
    colocada.  Es el numero que dice si el puño agarra o solo lo parece."""
    clear_fingers(arm, side)
    update()
    f_local, d_local, f_arm = measure_socket_vec(arm, side, curl_vec("grip"), signs)
    pads = pad_points(arm, meshes, base, side, f_arm)
    clear_fingers(arm, side)
    update()
    sock = grip_socket(side)
    print("BUILD informe de agarre (%s), holgura a la superficie del arma:" % side)
    for key in ("f_index", "f_middle", "f_ring", "f_pinky", "thumb", "palm"):
        if key not in pads:
            continue
        vals = [(surf_gap(bvh, sock @ c), c) for c in pads[key]]
        g, worst = min(vals, key=lambda t: t[0])
        pos = sock @ worst
        print("   %-9s %+7.2f mm  (%3d puntos)  peor en arma=(%+.4f,%+.4f,%+.4f)"
              % (key, 1000.0 * g, len(pads[key]), pos.x, pos.y, pos.z))


def _cost_of(gaps: dict) -> float:
    """Coste del ajuste.  Aire = caro; hundirse mas de 1 mm = 12x mas caro.  La
    palma no entra (su contacto lo fija el tamaño de la mano, no la flexion) y el
    indice solo se penaliza si se mete DENTRO de algo (va extendido sobre el
    armazon, no agarra); su aire entra con peso bajo, para que entre dos ajustes
    equivalentes gane el que deja el indice mas cerca del armazon."""
    def cost(g):
        return g if g > 0.0 else (12.0 * (-g - 0.001) if g < -0.001 else 0.0)

    idx = gaps["f_index"]
    return (cost(gaps["f_middle"]) + cost(gaps["f_ring"]) + cost(gaps["f_pinky"])
            + 1.5 * max(0.0, -idx - 0.001) + 0.20 * max(0.0, idx - 0.001))


def _gaps_for(arm, meshes: list, base: dict, side: str, signs: dict, bvh: BVHTree,
              vec: tuple, s0: Matrix, combos: list) -> list:
    """Holguras de (dloc, roll) para una flexion `vec` dada.

    `measure_socket_vec` y `pad_points` solo dependen de `vec`, asi que se pagan
    UNA vez por flexion y no por candidato.  La holgura se mide sobre TODA la
    yema: recortar la yema a los puntos mas cercanos a la boca sin desplazar
    infravalora el hundimiento real (se probo: -0,7 mm estimados contra -1,9 mm
    medidos), y con el atajo de `surf_gap` medirla entera ya es barato."""
    clear_fingers(arm, side)
    update()
    _, _, f_arm = measure_socket_vec(arm, side, vec, signs)
    pads = pad_points(arm, meshes, base, side, f_arm)
    clear_fingers(arm, side)
    update()
    out = []
    for dloc, roll in combos:
        rot = Matrix.Rotation(math.radians(roll), 3, "Y")
        gaps = {}
        for key, pts in pads.items():
            g = 9.9
            for c in pts:
                g = min(g, surf_gap(bvh, s0 @ (rot @ c + dloc)))
            gaps[key] = g
        out.append((gaps, dloc, roll))
    return out


def refine_contact(arm, meshes: list, base: dict, side: str, signs: dict,
                   bvh: BVHTree, vec: tuple, dloc: Vector, roll: float) -> tuple:
    """Pone la YEMA de cada dedo que agarra a -0.3 mm de la cara delantera.

    El desplazamiento y el giro son rigidos para toda la mano, asi que no pueden
    corregir que un dedo sea 1,5 mm mas corto que otro: eso solo se arregla
    flexionando ese dedo un poco mas o un poco menos.  Se busca, por dedo, el
    factor de flexion que deja su holgura en el objetivo (sin aire y sin
    hundirse mas de 1 mm)."""
    s0 = frame_matrix(GRIP_CENTER, GRIP_AXIS, GRIP_PALM[side])
    rot = Matrix.Rotation(math.radians(roll), 3, "Y")
    v = list(vec)
    for f in ("f_middle", "f_ring", "f_pinky"):
        i = FINGERS.index(f) * 3
        best = None
        for step in range(21):
            k = 0.70 + 0.025 * step
            cand = list(v)
            for j in range(3):
                cand[i + j] = v[i + j] * k
            clear_fingers(arm, side)
            update()
            _, _, f_arm = measure_socket_vec(arm, side, tuple(cand), signs)
            pads = pad_points(arm, meshes, base, side, f_arm, only=(f,))
            clear_fingers(arm, side)
            update()
            g = min(surf_gap(bvh, s0 @ (rot @ c + dloc)) for c in pads[f])
            err = abs(g + 0.0003)
            if best is None or err < best[0]:
                best = (err, k, g)
        for j in range(3):
            v[i + j] = v[i + j] * best[1]
        print("BUILD contacto %-9s flexion x%.3f -> holgura %+.2f mm"
              % (f, best[1], 1000.0 * best[2]))
    return tuple(v)


def fit_grip(arm, meshes: list, base: dict, signs: dict, side: str, bvh: BVHTree) -> dict:
    """Busca la flexion de los tres dedos que agarran y el desplazamiento/giro de
    la boca que dejan sus YEMAS TOCANDO la empuñadura de verdad.

    Objetivo por dedo: holgura entre 0 y -1 mm (tocar, hundirse un pelo, nunca
    aire).  El indice no se puntua por aire: va extendido a lo largo del armazon
    y solo se penaliza si se mete DENTRO de algo.  Busqueda en dos pasadas
    (gruesa y fina) porque la superficie es suave: 10x mas barata y el mismo
    minimo."""
    global GRIP_OFFSET, GRIP_ROLL
    s0 = frame_matrix(GRIP_CENTER, GRIP_AXIS, GRIP_PALM[side])
    s0b = s0.to_3x3()
    best = None

    def consider(vec, scale, pinky_extra, combos, tag):
        nonlocal best
        found = _gaps_for(arm, meshes, base, side, signs, bvh, vec, s0, combos)
        for gaps, dloc, roll in found:
            score = _cost_of(gaps)
            if best is None or score < best["score"]:
                best = {"score": score, "scale": scale, "dloc": dloc, "roll": roll,
                        "gaps": gaps, "vec": vec, "offset_gun": s0b @ dloc,
                        "pinky_extra": pinky_extra}
        print("BUILD ajuste %-7s escala=%.2f pinky=%+4.1f -> score=%.4f"
              % (tag, scale, pinky_extra, best["score"]))

    coarse = [(Vector((dx, 0.0, dz)), roll)
              for dz in (0.012, 0.004, -0.004)
              for dx in (-0.008, 0.0, 0.008)
              for roll in (-24.0, -12.0, 0.0, 12.0)]
    for scale in (1.00, 1.06, 1.12):
        for pe in (0.0, 12.0, 24.0):
            consider(scale_curl(curl_vec("grip"), scale, pe), scale, pe, coarse, "grueso")

    bs, bp = best["scale"], best["pinky_extra"]
    bd, br = best["dloc"], best["roll"]
    fine = [(bd + Vector((dx, 0.0, dz)), br + roll)
            for dz in (-0.003, 0.0, 0.003)
            for dx in (-0.002, 0.0, 0.002)
            for roll in (-5.0, 0.0, 5.0)]
    for scale in (bs - 0.03, bs, bs + 0.03):
        for pe in (bp - 4.0, bp, bp + 4.0):
            consider(scale_curl(curl_vec("grip"), scale, pe), scale, pe, fine, "fino")

    ## Refinado POR DEDO: el desplazamiento rigido no puede igualar dedos de
    ## distinta longitud; la flexion de cada uno si.
    vec = refine_contact(arm, meshes, base, side, signs, bvh, best["vec"],
                         best["dloc"], best["roll"])
    final = _gaps_for(arm, meshes, base, side, signs, bvh, vec, s0,
                      [(best["dloc"] + Vector((dx, 0.0, dz)), best["roll"] + roll)
                       for dz in (-0.002, 0.0, 0.002)
                       for dx in (-0.002, 0.0, 0.002)
                       for roll in (-4.0, 0.0, 4.0)])
    for gaps, dloc, roll in final:
        score = _cost_of(gaps)
        if score < best["score"]:
            best = {"score": score, "scale": best["scale"], "dloc": dloc, "roll": roll,
                    "gaps": gaps, "vec": vec, "offset_gun": s0b @ dloc,
                    "pinky_extra": best["pinky_extra"]}

    CURL["grip"] = {f: tuple(best["vec"][FINGERS.index(f) * 3:FINGERS.index(f) * 3 + 3])
                    for f in FINGERS}
    GRIP_OFFSET = best["offset_gun"]
    GRIP_ROLL = best["roll"]
    print("BUILD ajuste: escala=%.2f dloc=%s roll=%+.0f score=%.4f"
          % (best["scale"], [round(v, 4) for v in best["dloc"]], best["roll"], best["score"]))
    return best


class Pose:
    def __init__(self) -> None:
        self.r_socket = grip_socket("R")
        self.l_socket = grip_socket("L")
        self.r_sh = SHOULDER_R.copy()
        self.l_sh = SHOULDER_L.copy()
        self.r_pole = POLE_R.copy()
        self.l_pole = POLE_L.copy()
        self.r_curl = curl_vec(REST_CURL["R"])
        self.l_curl = curl_vec(REST_CURL["L"])
        ## Contragiro del conjunto brazo en espacio del arma (matriz de rotacion
        ## alrededor del origen del arma).  Lo usa Inspect: el arma se gira -83
        ## grados sobre su vertical para ensenar la ventana de expulsion, y los
        ## brazos, que cuelgan del mismo BodyGive, se giran con ella.  Contragirar
        ## el hombro deja el antebrazo apuntando abajo en el mundo otra vez.
        self.counter = None


def set_world(arm, name: str, m: Matrix) -> None:
    pb = arm.pose.bones[name]
    pb.rotation_mode = "QUATERNION"
    pb.matrix = m
    update()


def apply_pose(arm, pose: Pose, sockets: dict, signs: dict) -> None:
    """Escribe la pose en el rig.  Padres antes que hijos y `update()` entre
    asignaciones: `pose_bone.matrix` se resuelve contra el padre VIVO.

    Este donante NO tiene clavicula: el hombro es la CABEZA del hueso
    `upper_arm`, y se coloca escribiendo su matriz completa (traslacion
    incluida), exactamente igual que hacia el constructor anterior con su hueso
    `shoulder`.  `chest` y `root` se quedan en reposo."""
    for side in ("R", "L"):
        sock = b_mat(pose.r_socket if side == "R" else pose.l_socket)
        hand_m = sock @ sockets[side][0].inverted()
        sh_g = pose.r_sh if side == "R" else pose.l_sh
        pole_g = pose.r_pole if side == "R" else pose.l_pole
        if pose.counter is not None:
            sh_g = pose.counter @ sh_g
            pole_g = pose.counter @ pole_g
        sh = b_point(sh_g)
        pole = b_point(pole_g)
        W = hand_m.translation.copy()
        E = solve_elbow(sh, W, UP_LEN, FORE_LEN, pole)
        set_world(arm, "upper_arm.%s" % side, frame_matrix(sh, (E - sh).normalized(), pole))
        set_world(arm, "forearm.%s" % side, frame_matrix(E, (W - E).normalized(), pole))
        palm = arm.pose.bones.get("palm.%s" % side)
        if palm is not None:
            palm.rotation_mode = "QUATERNION"
            palm.rotation_quaternion = Quaternion()
            palm.location = Vector()
        set_world(arm, "hand.%s" % side, hand_m)
        apply_fingers(arm, side, pose.r_curl if side == "R" else pose.l_curl,
                      signs[side], curl_vec(REST_CURL[side]))


def reset_pose(arm) -> None:
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = Vector()
        pb.rotation_quaternion = Quaternion()
        pb.scale = Vector((1.0, 1.0, 1.0))
    update()


# ===========================================================================
# bind: la pose de reposo del GLB es la de Idle t=0
# ===========================================================================
def propagate_rigid(arm, base: dict, targets: dict, root_name: str,
                    local_rot: dict | None = None) -> None:
    """Reparte la pose por los hijos de `root_name` EN ORDEN padre->hijo.

    Cada hueso se compone desde SU PADRE, no desde la raiz:
        T_hijo = T_padre * (B_padre^-1 * B_hijo) * q_local
    Componer todos desde la raiz colocaba las falanges como si la mano estuviera
    abierta: la flexion del padre no llegaba al hijo y el bind salia con los
    dedos estirados."""
    order = []
    queue = [root_name]
    while queue:
        n = queue.pop(0)
        for c in arm.data.bones[n].children:
            order.append(c.name)
            queue.append(c.name)
    for name in order:
        parent = arm.data.bones[name].parent.name
        T = targets[parent] @ base[parent].inverted() @ base[name]
        q = (local_rot or {}).get(name)
        if q is not None:
            T = T @ q.to_matrix().to_4x4()
        targets[name] = T


def bake_bind(arm, meshes: list, targets: dict) -> None:
    """Reescribe la pose de reposo con `targets` (espacio del arma) y REBAKEA la
    malla para que siga viendose igual.

    Skinning:  v_posed = sum w_i * (M_i * B_i^-1) * v_rest.
    Con B'_i = T_i y v'_rest = v_posed la malla en reposo queda donde estaba y
    las poses siguen dando lo mismo (el bind nuevo ES la pose que se le pase)."""
    rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}
    for mesh in meshes:
        vgs = [vg.name for vg in mesh.vertex_groups]
        verts = []
        for v in mesh.data.vertices:
            acc = Vector()
            total = 0.0
            for g in v.groups:
                name = vgs[g.group]
                T = targets.get(name)
                if T is None or g.weight <= 0.0:
                    continue
                acc += (T @ rest[name].inverted() @ v.co) * g.weight
                total += g.weight
            verts.append(acc / total if total > 1e-9 else v.co.copy())
        flat = []
        for v in verts:
            flat += [v.x, v.y, v.z]
        mesh.data.vertices.foreach_set("co", flat)
        mesh.data.update()

    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm.data.edit_bones
    for name, T in targets.items():
        eb = ebs.get(name)
        if eb is None:
            continue
        length = eb.length
        head = T.translation.copy()
        tail = head + (T.to_3x3() @ Vector((0.0, 1.0, 0.0))).normalized() * length
        eb.head = head
        eb.tail = tail
        eb.align_roll(T.to_3x3() @ Vector((0.0, 0.0, 1.0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    update()

    worst = 0.0
    for name, T in targets.items():
        b = arm.data.bones.get(name)
        if b is None:
            continue
        got = b.matrix_local
        worst = max(worst, max(abs(got[i][j] - T[i][j]) for i in range(4) for j in range(4)))
    print("BUILD bind: desviacion maxima de la pose de reposo = %.2e" % worst)
    assert worst < 1e-4, "BUILD ABORTA: el bind no reproduce la pose pedida"


# ===========================================================================
# canales
# ===========================================================================
def smooth(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


class Track:
    """Trayectoria de la boca de una mano: claves (t, Matrix, vector de flexion)
    con interpolacion suave de traslacion, slerp de rotacion y lerp de dedos."""

    def __init__(self, keys):
        self.keys = keys

    def at(self, t: float):
        ks = self.keys
        if t <= ks[0][0]:
            return ks[0][1], ks[0][2]
        if t >= ks[-1][0]:
            return ks[-1][1], ks[-1][2]
        for i in range(len(ks) - 1):
            t0, m0, c0 = ks[i]
            t1, m1, c1 = ks[i + 1]
            if t0 <= t <= t1:
                k = smooth((t - t0) / (t1 - t0)) if t1 > t0 else 1.0
                return blend_matrix(m0, m1, k), lerp_vec(c0, c1, k)
        return ks[-1][1], ks[-1][2]


IDLE_L_POS = Vector((-0.215, -0.565, 0.135))
L_OUT_LEFT = Vector((-0.305, -0.455, 0.075))
L_UNDER = Vector((-0.040, -0.250, 0.030))
L_RELEASE = Vector((-0.055, -0.036, 0.024))

## Direccion del hueso `hand` y pista de palma para las poses libres (la mano no
## agarra nada): la izquierda cuelga hacia abajo-adelante con la palma al cuerpo.
L_FREE_DIR = Vector((-0.18, -0.88, -0.44))
L_FREE_PALM = Vector((0.94, -0.28, 0.18))
## Al pasar por detras del arma (transiciones) la mano apunta mas al morro.
L_MID_DIR = Vector((0.30, -0.55, -0.78))

MAG_INSERT_FROM = 0.170   # constante de Glock.gd
MAG_FREE = 0.070          # GlockWeapon.MAG_TRAVEL


def build_tracks(sockets: dict) -> dict:
    d_local = sockets["L"][1]

    def free_at(pos, hand_dir=None, palm=None):
        return socket_from_dir(pos, hand_dir or L_FREE_DIR, palm or L_FREE_PALM, d_local)

    relay = [
        (0.00, free_at(IDLE_L_POS), curl_vec("relax")),
        (0.13, free_at(L_OUT_LEFT), curl_vec("relax")),
        (0.22, free_at(L_RELEASE + Vector((0.0, -0.01, -0.01)),
                       Vector((0.42, -0.30, -0.86)), Vector((0.86, 0.30, -0.40))),
         curl_vec("point")),
        (0.28, free_at(L_RELEASE, Vector((0.42, -0.30, -0.86)), Vector((0.86, 0.30, -0.40))),
         curl_vec("point")),
        (0.40, free_at(L_UNDER, L_MID_DIR), curl_vec("point")),
        (0.52, mag_socket(0.030), curl_vec("mag")),
        (0.62, mag_socket(MAG_FREE), curl_vec("grip")),
        (0.78, free_at(L_OUT_LEFT), curl_vec("relax")),
        (0.94, mag_socket(MAG_INSERT_FROM + 0.012), curl_vec("mag")),
        (1.02, mag_socket(MAG_INSERT_FROM), curl_vec("mag")),
        (1.22, mag_socket(MAG_INSERT_FROM * 0.30), curl_vec("mag")),
        (1.40, mag_socket(0.0), curl_vec("mag")),
    ]
    reload_keys = relay + [
        (1.52, mag_socket(-0.012), curl_vec("grip")),
        (1.62, free_at(L_UNDER + Vector((0.0, -0.03, 0.02)), L_MID_DIR), curl_vec("relax")),
        (1.72, free_at(L_OUT_LEFT, L_MID_DIR), curl_vec("relax")),
        (2.10, free_at(IDLE_L_POS), curl_vec("relax")),
    ]
    empty_keys = relay + [
        (1.48, mag_socket(-0.012), curl_vec("mag")),
        (1.58, slide_socket(0.0, lift=0.010), curl_vec("slide")),
        (1.66, slide_socket(-SLIDE_TRAVEL, lift=0.010), curl_vec("slide")),
        (1.72, slide_socket(-SLIDE_TRAVEL, lift=0.010), curl_vec("slide")),
        (1.80, slide_socket(-SLIDE_TRAVEL * 0.35, lift=0.012), curl_vec("slide")),
        (1.94, free_at(L_UNDER, L_MID_DIR), curl_vec("relax")),
        (2.35, free_at(IDLE_L_POS), curl_vec("relax")),
    ]
    inspect_keys = [
        (0.00, free_at(IDLE_L_POS), curl_vec("relax")),
        (0.07, free_at(L_UNDER, L_MID_DIR), curl_vec("relax")),
        (0.13, slide_socket(0.0, lift=0.008), curl_vec("slide")),
        (0.22, slide_socket(-0.012, lift=0.008), curl_vec("slide")),
        (0.30, slide_socket(-SLIDE_TRAVEL, lift=0.008), curl_vec("slide")),
        (0.62, slide_socket(-SLIDE_TRAVEL, lift=0.008), curl_vec("slide")),
        (1.20, slide_socket(-SLIDE_TRAVEL, lift=0.008), curl_vec("slide")),
        (1.26, slide_socket(-SLIDE_TRAVEL * 0.30, lift=0.012), curl_vec("slide")),
        (1.40, free_at(L_UNDER, L_MID_DIR), curl_vec("relax")),
        (1.70, free_at(L_OUT_LEFT), curl_vec("relax")),
        (2.00, free_at(IDLE_L_POS), curl_vec("relax")),
    ]
    return {
        "Reload": Track(reload_keys),
        "ReloadEmpty": Track(empty_keys),
        "Inspect": Track(inspect_keys),
    }


# ===========================================================================
# poses por clip
# ===========================================================================
IDLE_D_LOCAL = Vector((0.0, 0.0, 1.0))


def idle_pose(t: float, tracks: dict | None = None) -> Pose:
    p = Pose()
    ph = 2.0 * math.pi * t / 3.0
    breath = math.sin(ph)
    ## Respiracion: el arma tambien respira (PoseRoot), asi que la mano se queda
    ## PLANTADA en la empuñadura y lo que se mueve es el hombro y el codo.
    p.r_sh = SHOULDER_R + Vector((0.0, 0.0016 * breath, 0.0010 * math.sin(2.0 * ph)))
    p.l_sh = SHOULDER_L + Vector((0.0, 0.0014 * breath, 0.0))
    p.r_socket = grip_socket("R", roll_deg=0.30 * breath)
    if tracks is None:
        p.l_socket = socket_from_dir(
            IDLE_L_POS + Vector((0.0012 * breath, 0.0, 0.0016 * math.sin(ph + 1.0))),
            L_FREE_DIR, L_FREE_PALM, IDLE_D_LOCAL)
        p.l_curl = curl_vec("relax")
    return p


def make_clip_fn(name: str, tracks: dict):
    if name == "Idle":
        def fn(t):
            return idle_pose(t)
        return fn
    if name == "Fire":
        def fn(t):
            p = idle_pose(0.0)
            ## El arma la mueve GlockRecoil (pico ~0.06 s, 5.7 grados de cabeceo).
            ## El brazo absorbe una fraccion, con retardo y con vuelta.
            kick = 0.0
            ks = [(0.000, 0.0), (0.018, 0.15), (0.055, 1.0), (0.100, 0.55),
                  (0.150, -0.10), (0.200, 0.03), (0.260, 0.0)]
            if t <= ks[0][0]:
                kick = ks[0][1]
            elif t >= ks[-1][0]:
                kick = ks[-1][1]
            else:
                for i in range(len(ks) - 1):
                    if ks[i][0] <= t <= ks[i + 1][0]:
                        kick = ks[i][1] + (ks[i + 1][1] - ks[i][1]) * smooth(
                            (t - ks[i][0]) / (ks[i + 1][0] - ks[i][0]))
                        break
            rot = Matrix.Rotation(math.radians(2.2) * kick, 4, Vector((1.0, 0.0, 0.0)))
            m = p.r_socket @ rot
            m.translation = m.translation + Vector((0.0, 0.0011 * kick, 0.0016 * kick))
            p.r_socket = m
            p.r_sh = SHOULDER_R + Vector((0.0005 * kick, -0.0012 * kick, 0.0022 * kick))
            m2 = p.l_socket.copy()
            m2.translation = m2.translation + Vector((0.0, 0.0016 * kick, 0.0022 * kick))
            p.l_socket = m2
            p.l_sh = SHOULDER_L + Vector((0.0, -0.0008 * kick, 0.0014 * kick))
            return p
        return fn
    track = tracks[name]
    dur = {"Reload": 2.10, "ReloadEmpty": 2.35, "Inspect": 2.00}[name]

    def fn(t):
        p = idle_pose(0.0)
        sock, curl = track.at(t)
        p.l_socket = sock
        p.l_curl = curl
        ## El hombro izquierdo acompaña al brazo: sube y va al centro mientras
        ## la mano trabaja en el arma, y vuelve al colgar.  Sin esto el codo se
        ## rompe en cuanto la mano sube al brocal.
        up = min(1.0, max(0.0, (t - 0.04) / 0.26))
        if t > dur - 0.30:
            up *= max(0.0, (dur - t) / 0.30)
        p.l_sh = SHOULDER_L + Vector((0.030, 0.020, -0.030)) * up
        return p
    return fn


# ===========================================================================
# main
# ===========================================================================
def parse_args() -> argparse.Namespace:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=str(OUT))
    p.add_argument("--donor", default=str(DONOR))
    p.add_argument("--bind-only", type=int, default=0)
    p.add_argument("--grip-report", type=int, default=0,
                   help="1 = informe por dedo del contacto con la empuñadura")
    p.add_argument("--verify", type=int, default=0)
    p.add_argument("--verify-only", default="", help="valida un GLB ya escrito y sale")
    p.add_argument("--tex", type=int, default=1024,
                   help="lado al que se lleva TODA textura mayor que el (0 = no tocar)")
    p.add_argument("--grip-slide", type=float, default=0.0)
    p.add_argument("--grip-roll", type=float, default=0.0)
    p.add_argument("--grip-off", default="0,0,0")
    return p.parse_args(argv)


def load_donor(donor: Path) -> tuple:
    """Importa el donante y devuelve (armadura, mallas, matriz de mundo)."""
    reset_scene()
    objs = import_gltf(donor)
    arm = next(o for o in objs if o.type == "ARMATURE")
    meshes = [o for o in objs if o.type == "MESH"
              and any(m.type == "ARMATURE" for m in o.modifiers)]
    meshes.sort(key=lambda o: o.name)
    assert len(meshes) in (1, 2), "BUILD ABORTA: %d mallas skinned" % len(meshes)
    print("BUILD donante:", donor.name, "| armadura", arm.name,
          "| mallas", [m.name for m in meshes])
    world = arm.matrix_world.copy()
    strip_donor(arm, meshes, world)
    return arm, meshes, world


def prepare(arm, meshes: list, world: Matrix) -> None:
    """Del import crudo al rig metrico con la pose del autor como reposo."""
    global TIP_LOCAL
    TIP_LOCAL = measure_tips(arm)
    strip_leaves(arm)
    rename_bones(arm, meshes)
    normalize_world(arm, meshes, world)
    ## REBASE: el bind del donante es una T-pose y su POSE es la de primera
    ## persona.  Se hornea la pose del autor como nuevo reposo para que el rig
    ## sea un rig normal (reposo == lo que se ve) y metrico.
    targets = {pb.name: pb.matrix.copy() for pb in arm.pose.bones}
    bake_bind(arm, meshes, targets)
    TIP_LOCAL = {canonical(k) or k: v for k, v in TIP_LOCAL.items()}
    drop_extra_uvs(meshes)
    reset_pose(arm)
    for mesh in meshes:
        for poly in mesh.data.polygons:
            poly.use_smooth = True
        if hasattr(mesh.data, "use_auto_smooth"):
            mesh.data.use_auto_smooth = True
            mesh.data.auto_smooth_angle = math.radians(45.0)
    print("BUILD tras preparar: %d huesos, %d mallas, tris=%d" % (
        len(arm.data.bones), len(meshes),
        sum(sum(len(p.vertices) - 2 for p in m.data.polygons) for m in meshes)))


def main() -> None:
    args = parse_args()
    if args.verify_only:
        verify(Path(args.verify_only))
        return
    out = Path(args.out)
    if not out.is_absolute():
        out = REPO / out
    donor = Path(args.donor)
    if not donor.is_absolute():
        donor = REPO / donor
    if not donor.exists():
        raise SystemExit(
            "BUILD ABORTA: falta el donante %s\n"
            "  Es CC-BY-4.0 de BAMEN, 'FREE [FPS Arms] GameReady - RIGGED'\n"
            "  https://sketchfab.com/3d-models/free-fps-arms-gameready-rigged-296d30fc705b4dff85c2c8a2d2724e7f\n"
            "  y NO esta en el repo (downloads/ es gitignored)." % donor)

    global GRIP_CENTER, GRIP_AXIS, IDLE_D_LOCAL, UP_LEN, FORE_LEN
    GRIP_CENTER = GRIP_CENTER + GRIP_AXIS * args.grip_slide \
        + Vector([float(v) for v in args.grip_off.split(",")])

    arm, meshes, world = load_donor(donor)
    prepare(arm, meshes, world)
    UP_LEN = arm.data.bones["upper_arm.R"].length
    FORE_LEN = arm.data.bones["forearm.R"].length
    print("BUILD longitudes: upper_arm=%.4f forearm=%.4f" % (UP_LEN, FORE_LEN))

    ## La malla se evalua por el modificador de armadura: apagarlo durante el
    ## autoreado acelera el depsgraph.  Se vuelve a encender antes de exportar
    ## (si no, el glTF pierde la piel).
    mods = []
    for mesh in meshes:
        m = next((x for x in mesh.modifiers if x.type == "ARMATURE"), None)
        if m is not None:
            m.show_viewport = False
            mods.append(m)

    # --- signos y bocas -----------------------------------------------------
    reset_pose(arm)
    measure_flex_axes(arm)
    signs = {s: measure_curl_signs(arm, meshes, s) for s in ("R", "L")}
    bvh = gun_grip_bvh()
    base0 = {b.name: b.matrix_local.copy() for b in arm.data.bones}
    fit = fit_grip(arm, meshes, base0, signs["R"], "R", bvh)
    print("BUILD ajuste del puño: flexion x%.2f  desplazamiento=%s  giro=%+.0f deg  "
          "holguras(mm) medio=%+.1f anular=%+.1f meñique=%+.1f indice=%+.1f palma=%+.1f"
          % (fit["scale"], [round(v, 4) for v in fit["dloc"]], fit["roll"],
             1000 * fit["gaps"]["f_middle"], 1000 * fit["gaps"]["f_ring"],
             1000 * fit["gaps"]["f_pinky"], 1000 * fit["gaps"]["f_index"],
             1000 * fit["gaps"]["palm"]))
    sockets = {}
    for s in ("R", "L"):
        clear_fingers(arm, s)
        update()
        sockets[s] = measure_socket(arm, s, "grip", signs[s])
        clear_fingers(arm, s)
        update()
    reset_pose(arm)
    IDLE_D_LOCAL = sockets["L"][1]
    ## El informe va ANTES de rehornear el bind: despues, las matrices de reposo
    ## que usa la medida ya no son las del donante.
    if args.grip_report:
        for _s in ("R", "L"):
            grip_report(arm, meshes, base0, _s, signs[_s], bvh)
    print("BUILD signos R:", {k: int(v) for k, v in sorted(signs["R"].items())})

    # --- bind = Idle t=0 ----------------------------------------------------
    bind = idle_pose(0.0)
    base = {b.name: b.matrix_local.copy() for b in arm.data.bones}
    targets = dict(base)
    for side in ("R", "L"):
        sock = b_mat(bind.r_socket if side == "R" else bind.l_socket)
        hand_m = sock @ sockets[side][0].inverted()
        sh = b_point(bind.r_sh if side == "R" else bind.l_sh)
        pole = b_point(bind.r_pole if side == "R" else bind.l_pole)
        W = hand_m.translation.copy()
        E = solve_elbow(sh, W, UP_LEN, FORE_LEN, pole)
        targets["upper_arm.%s" % side] = frame_matrix(sh, (E - sh).normalized(), pole)
        targets["forearm.%s" % side] = frame_matrix(E, (W - E).normalized(), pole)
        targets["hand.%s" % side] = hand_m
        ## El bind tiene que tener los dedos YA cerrados: la flexion de reposo
        ## entra como rotacion local de cada falange.
        propagate_rigid(arm, base, targets, "hand.%s" % side,
                        finger_rots(side, curl_vec(REST_CURL[side]), ZERO_VEC, signs[side]))
    bake_bind(arm, meshes, targets)
    _g2b = GUN_TO_BLENDER.inverted()
    for _side in ("R", "L"):
        _sock = b_mat(bind.r_socket if _side == "R" else bind.l_socket)
        _hand = _sock @ sockets[_side][0].inverted()
        _sh = b_point(bind.r_sh if _side == "R" else bind.l_sh)
        _pole = b_point(bind.r_pole if _side == "R" else bind.l_pole)
        _W = _hand.translation.copy()
        _E = solve_elbow(_sh, _W, UP_LEN, FORE_LEN, _pole)
        print("BUILD debug brazo %s: hombro(arma)=%s codo(arma)=%s muñeca(arma)=%s | "
              "f_local.t=%s" % (
                  _side, [round(x, 3) for x in (_g2b @ _sh)],
                  [round(x, 3) for x in (_g2b @ _E)],
                  [round(x, 3) for x in (_g2b @ _W)],
                  [round(x, 3) for x in sockets[_side][0].translation]))

    # --- clips --------------------------------------------------------------
    if not args.bind_only:
        tracks = build_tracks(sockets)
        if arm.animation_data is None:
            arm.animation_data_create()
        arm.animation_data.action = None
        for act in list(bpy.data.actions):
            bpy.data.actions.remove(act)
        for name in ("Idle", "Fire", "Reload", "ReloadEmpty", "Inspect"):
            dur = {"Idle": 3.00, "Fire": 0.26, "Reload": 2.10,
                   "ReloadEmpty": 2.35, "Inspect": 2.00}[name]
            fn = make_clip_fn(name, tracks)
            act = bpy.data.actions.new(name)
            act.use_fake_user = True
            arm.animation_data.action = act
            n = int(round(dur * FPS))
            for f in range(n + 1):
                apply_pose(arm, fn(f / FPS), sockets, signs)
                for pb in arm.pose.bones:
                    pb.keyframe_insert("location", frame=f, group=pb.name)
                    pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            for fc in act.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = "LINEAR"
            print("BUILD clip %-12s %d frames (%.2f s) curvas=%d"
                  % (name, n + 1, dur, len(act.fcurves)))
        arm.animation_data.action = bpy.data.actions["Idle"]

    # --- NLA: el exportador glTF nombra las animaciones con la PISTA NLA, no
    #     con la accion, asi que no puede quedar ninguna.
    ad = arm.animation_data
    if ad is not None:
        for track in list(ad.nla_tracks):
            print("BUILD fuera pista NLA:", track.name)
            ad.nla_tracks.remove(track)

    for m in mods:
        m.show_viewport = True

    if args.tex > 0:
        for img in bpy.data.images:
            if img.size[0] and max(img.size) > args.tex:
                print("BUILD textura %s %s -> %d" % (img.name, tuple(img.size), args.tex))
                img.scale(args.tex, args.tex)

    arm.name = "ArmsRig"
    arm.data.name = "ArmsRig"
    for mesh in meshes:
        mesh.name = "Arms_" + mesh.name
    out.parent.mkdir(parents=True, exist_ok=True)
    activate(arm)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        use_selection=False,
        export_apply=False,
        export_animations=not args.bind_only,
        export_animation_mode="ACTIONS",
        export_nla_strips=False,
        export_frame_range=False,
        export_force_sampling=True,
        export_frame_step=1,
        export_bake_animation=False,
        export_skins=True,
        export_yup=True,
        export_image_format="AUTO",
        export_optimize_animation_size=False,
        export_anim_single_armature=True,
        export_influence_nb=4,
    )
    print("BUILD escrito: %s (%.1f KB)" % (out, out.stat().st_size / 1024.0))
    if args.verify:
        verify(out)


# ===========================================================================
# verificacion del GLB: se PARSEA el archivo, no se le pregunta a Blender
# ===========================================================================
CLIPS = {"Idle": 3.00, "Fire": 0.26, "Reload": 2.10, "ReloadEmpty": 2.35,
         "Inspect": 2.00}
TRI_MIN, TRI_MAX = 8000, 20000


def glb_json(data: bytes) -> dict:
    n = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20:20 + n])


def glb_bin(data: bytes) -> bytes:
    """Trozo BIN del GLB.  Los `byteOffset` de los bufferViews son relativos a
    ESTE trozo, no al archivo: sin sumar su origen las imagenes se leen a
    partir del sitio equivocado."""
    off = 12
    while off + 8 <= len(data):
        length = struct.unpack("<I", data[off:off + 4])[0]
        kind = data[off + 4:off + 8]
        if kind == b"BIN\x00":
            return data[off + 8:off + 8 + length]
        off += 8 + length
    return b""


def png_size(blob: bytes) -> tuple:
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        return (0, 0)
    w, h = struct.unpack(">II", blob[16:24])
    return (w, h)


def verify(path: Path) -> None:
    data = path.read_bytes()
    gltf = glb_json(data)
    blob_all = glb_bin(data)
    ok = True

    def bad(msg: str) -> None:
        nonlocal ok
        ok = False
        print("  FALLO:", msg)

    print("=" * 70)
    print("VERIFY", path, "(%.1f KB)" % (len(data) / 1024.0))
    meshes = gltf.get("meshes", [])
    prims = [(m.get("name"), p) for m in meshes for p in m["primitives"]]
    tris = sum(gltf["accessors"][p["indices"]]["count"] // 3 for _, p in prims)
    print("  meshes    :", [m.get("name") for m in meshes], "prims:", len(prims),
          "tris:", tris)
    if len(meshes) > 2:
        bad("mas de 2 mallas")
    if not (TRI_MIN <= tris <= TRI_MAX):
        bad("triangulos fuera de [%d, %d]" % (TRI_MIN, TRI_MAX))
    for name, p in prims:
        acc = gltf["accessors"][p["attributes"]["POSITION"]]
        print("    %-22s verts=%d min=%s max=%s" % (
            name, acc["count"], [round(v, 3) for v in acc["min"]],
            [round(v, 3) for v in acc["max"]]))
    mats = gltf.get("materials", [])
    print("  materiales:", [m.get("name") for m in mats])
    if len(mats) > 2:
        bad("mas de 2 materiales")
    for im in gltf.get("images", []):
        bv = gltf["bufferViews"][im["bufferView"]]
        start = bv.get("byteOffset", 0)
        blob = blob_all[start:start + bv["byteLength"]]
        w, h = png_size(blob)
        print("  imagen    : %-34s %dx%d bytes=%d mime=%s"
              % (im.get("name"), w, h, bv["byteLength"], im.get("mimeType")))
        if w == 0:
            bad("no se pudo leer el tamaño de %s" % im.get("name"))
        if w > 1024 or h > 1024:
            bad("textura %s a %dx%d (>1024)" % (im.get("name"), w, h))
    skins = gltf.get("skins", [])
    print("  skins     :", len(skins), "joints:", [len(s["joints"]) for s in skins])
    if len(skins) != 1:
        bad("se esperaba exactamente 1 skin")
    joints = [gltf["nodes"][j].get("name", "") for s in skins for j in s["joints"]]
    end = [j for j in joints if "_end" in j or j.endswith("_end")]
    print("  huesos    :", len(joints), "| hojas _end:", end or "ninguna")
    if end:
        bad("quedan huesos hoja _end")
    if not (40 <= len(joints) <= 50):
        bad("numero de huesos fuera de [40, 50]")
    for s in skins:
        for j in s["joints"]:
            nd = gltf["nodes"][j]
            for c in nd.get("children", []):
                if gltf["nodes"][c].get("name", "") not in joints:
                    bad("hueso %s tiene un hijo que no es joint" % nd.get("name"))
    for a in gltf.get("animations", []):
        tmax = max(gltf["accessors"][s["input"]]["max"][0] for s in a["samplers"])
        want = CLIPS.get(a["name"])
        flag = "" if want is not None and abs(tmax - want) < 1e-3 else "  <-- MAL"
        print("  clip %-12s dur=%.4f s (objetivo %s) canales=%d%s"
              % (a["name"], tmax, want, len(a["channels"]), flag))
        if want is None or abs(tmax - want) >= 1e-3:
            bad("clip %s con duracion %.4f" % (a["name"], tmax))
    names = sorted(a["name"] for a in gltf.get("animations", []))
    want = sorted(CLIPS)
    print("  nombres   :", names)
    if names != want:
        bad("los clips no son exactamente %s" % want)
    scene = gltf["scenes"][gltf.get("scene", 0)]
    for root in scene["nodes"]:
        nd = gltf["nodes"][root]
        trs = [k for k in ("translation", "rotation", "scale", "matrix") if k in nd]
        print("  raiz      : %-12s %s" % (nd.get("name"), trs or "sin T/R/S (identidad)"))
        if trs:
            bad("el nodo raiz %s trae %s" % (nd.get("name"), trs))
    print("  nodos     : %d" % len(gltf.get("nodes", [])))
    print("VERIFY", "OK" if ok else "FALLO")
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
