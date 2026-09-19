#!/usr/bin/env python3
"""ARMS DE PRODUCCION: brazos en primera persona para el simulador de Glock 19.

    blender --background --python tools/build_arms.py -- --out assets/models/fps_arms.glb --grip-report 1 --verify 1
    blender --background --python tools/build_arms.py -- --out /tmp/dj.glb --bind-only 1
    blender --background --python tools/build_arms.py -- --verify-only assets/models/fps_arms.glb

DONANTE  (NO esta en el repo: `downloads/` es gitignored)
---------------------------------------------------------
    downloads/models/djmaesen_animated_pistol/extracted/scene.gltf
    DJMaesen, "animated pistol"
    https://sketchfab.com/3d-models/animated-pistol-bd896167e7ca44f19597d3afe6a8d83f
    Licencia, textual del `license.txt` que viene en la descarga:
        license type:	CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)
        requirements:	Author must be credited. Commercial use is allowed.
    CC-BY-4.0: atribucion OBLIGATORIA (la linea exacta esta en
    `CREDITS_MODELS.md`), uso comercial permitido.
    Un checkout limpio tiene que bajar el ZIP de esa URL y descomprimirlo en
    `downloads/models/djmaesen_animated_pistol/extracted/`.

QUE HACE
--------
Del donante se queda SOLO su malla de brazos (`Object_83`, 13.536 tris, 1
material `arms`), su esqueleto (51 huesos, todos deform, cero constraints) y su
POSE DE AGARRE A DOS MANOS, que es lo que el dueño del repo señala como "decente
como un juego decente".  La Beretta y sus nodos se tiran.

La pose la trae el donante, no una busqueda: el constructor muestrea su
animacion fotograma a fotograma y se queda con los brazos RELATIVOS A SU PISTOLA
(el donante anima el arma por su cuenta y los brazos por la suya: en runtime el
arma la mueve `Glock.gd` y los brazos cuelgan de `BodyGive`, asi que lo que sirve
es la pose relativa al arma).  Eso se coloca sobre NUESTRA `g19_pistol.glb` con
UNA transformacion RIGIDA, calculada midiendo el tunel del puño en la malla, y
solo se busca el desplazamiento y el giro de la boca: la flexion de los dedos NO
se toca nunca para "cuadrar" el contacto.

Los cinco clips salen de ahi: `Idle` y `Fire` son la pose de agarre (fotograma 0)
mas respiracion y latigazo, y `Reload` / `ReloadEmpty` / `Inspect` son las
ventanas de gesto del donante retimadas a nuestras duraciones exactas.

Salida: `assets/models/fps_arms.glb`, 1 malla, 1 material, esqueleto deform de 51
huesos, 5 clips exactos (3.00 / 0.26 / 2.10 / 2.35 / 2.00 s), autorado en espacio
del arma con la raiz en identidad.
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

DONOR = REPO / "downloads" / "models" / "djmaesen_animated_pistol" / "extracted" / "scene.gltf"
GUN = REPO / "assets" / "models" / "g19_pistol.glb"
OUT = REPO / "assets" / "models" / "fps_arms.glb"

## Espacio del arma -> espacio de Blender: (x,y,z)_arma -> (x,-z,y)_blender.
GUN_TO_BLENDER = Matrix.Rotation(math.radians(90.0), 4, "X")

FPS = 100  # 100 fps: 0.26 / 1.02 / 1.40 / 1.72 / 2.35 s caen en frames enteros

## ---------------------------------------------------------------------------
## MEDIDAS DEL ARMA (espacio del arma, metros), medidas sobre NUESTRA
## `g19_pistol.glb`: no de la ficha del fabricante.
## ---------------------------------------------------------------------------
GRIP_AXIS = Vector((-0.0041, 0.9529, -0.3032)).normalized()
GRIP_CENTER = Vector((0.0, -0.0425, 0.0390))
GRIP_PALM = {"R": Vector((-0.85, 0.0, -0.53)).normalized(),
             "L": Vector((0.85, 0.0, -0.53)).normalized()}
SLIDE_REAR_Z = 0.0803
SLIDE_TOP_Y = 0.0634
SLIDE_TRAVEL = 0.039
MAG_RELEASE = Vector((-0.0130, -0.0182, 0.0322))


## Espacio del arma -> espacio de Blender.  El constructor razona TODO en espacio
## del arma (+Y arriba, -Z al morro) y convierte al final: el exportador glTF
## deshace justo esa conversion, asi que el GLB sale en espacio del arma con el
## nodo raiz en IDENTIDAD.
def b_point(v) -> Vector:
    return GUN_TO_BLENDER @ Vector(v)


def b_mat(m: Matrix) -> Matrix:
    return GUN_TO_BLENDER @ m


# ===== utilidades =====
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
    W = arm.matrix_world.copy()
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
            out.setdefault(tag, []).append(inv @ (W @ p))
    return out

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
        ## La LONGITUD se conserva (no afecta al skinning) y el resto se escribe
        ## con la matriz entera: con donantes que traen la escala metida en el
        ## bind, ir por cabeza/cola/roll no reproduce la matriz pedida.
        R = T.to_3x3().normalized()
        M = R.to_4x4()
        M.translation = T.translation
        ## La cola NO se toca despues: reasignarla recalcula el roll y entonces
        ## `matrix_local` deja de reproducir la matriz pedida (la longitud no
        ## afecta al skinning ni al glTF, que no guarda longitudes de hueso).
        eb.matrix = M
    bpy.ops.object.mode_set(mode="OBJECT")
    update()

    ## Se compara lo que de verdad manda en el skinning: la CABEZA (traslacion) y
    ## los EJES del hueso.  Comparar la 4x4 entera mezcla la longitud (que no
    ## afecta) y la escala que el donante trae metida en el bind.
    worst_head, worst_axis, worst_name = 0.0, 0.0, ""
    for name, T in targets.items():
        b = arm.data.bones.get(name)
        if b is None:
            continue
        dh = (b.head_local - T.translation).length
        Ra, Rb = b.matrix_local.to_3x3(), T.to_3x3()
        da = max((Ra.col[i].normalized() - Rb.col[i].normalized()).length for i in range(3))
        if dh > worst_head or da > worst_axis:
            if dh > worst_head:
                worst_head = dh
            if da > worst_axis:
                worst_axis = da
            worst_name = name
    print("BUILD bind: desviacion maxima cabeza=%.2e m  ejes=%.2e  (peor: %s)"
          % (worst_head, worst_axis, worst_name))
    assert worst_head < 1e-4 and worst_axis < 1e-3, \
        "BUILD ABORTA: el bind no reproduce la pose pedida (%s)" % worst_name

def reset_pose(arm) -> None:
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = Vector()
        pb.rotation_quaternion = Quaternion()
        pb.scale = Vector((1.0, 1.0, 1.0))
    update()

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


# ===========================================================================
# donante DJMaesen: nombres, cadenas y medida del puño
# ===========================================================================
DJ_FINGERS = ("f_index", "f_middle", "f_ring", "f_pinky")
FINGERS = DJ_FINGERS  # `pad_points` viene del builder de BAMEN y usa este nombre


def thumb_bones(side: str) -> list:
    return thumb_chain(side)


def canonical(name: str) -> str | None:
    """Nombre canonico de un hueso del donante, o None si hay que tirarlo."""
    if name == "_rootJoint":
        return "root"
    m = re.match(r"^([LR])_(arm|elbow|forearm|wrist|palm)_\d+$", name)
    if m:
        side = m.group(1)
        return {"arm": "upper_arm", "elbow": "elbow", "forearm": "forearm",
                "wrist": "hand", "palm": "palm"}[m.group(2)] + "." + side
    m = re.match(r"^([LR])_(thumb|point|middle|ring|pink)(\d)_\d+$", name)
    if m:
        side, i = m.group(1), int(m.group(3))
        if m.group(2) == "thumb":
            return "thumb.%02d.%s" % (i, side)
        f = {"point": "f_index", "middle": "f_middle", "ring": "f_ring",
             "pink": "f_pinky"}[m.group(2)]
        return "%s.%02d.%s" % (f, i, side)
    return None


def chain(side: str, finger: str) -> list:
    return ["%s.%02d.%s" % (finger, i, side) for i in (1, 2, 3, 4)]


def thumb_chain(side: str) -> list:
    return ["thumb.%02d.%s" % (i, side) for i in (1, 2, 3, 4)]


def palm_normal(arm, side: str) -> Vector:
    """Normal palmar a partir de la quiralidad: Y_mano x (indice -> menique)."""
    hand = arm.pose.bones["hand.%s" % side]
    ydir = (arm.matrix_world.to_3x3() @ hand.matrix.to_3x3()
            @ Vector((0.0, 1.0, 0.0))).normalized()
    idx = head_world(arm, "f_index.01.%s" % side)
    pnk = head_world(arm, "f_pinky.01.%s" % side)
    n = ydir.cross(pnk - idx).normalized()
    return n if side == "R" else -n


def head_world(arm, name: str) -> Vector:
    return arm.matrix_world @ arm.pose.bones[name].head


def fist_frame(arm, side: str) -> Matrix:
    """Marco rigido del puño MEDIDO EN METROS (espacio de mundo).

    El donante trae la armadura a x100 y la malla al mismo factor: medir en
    espacio de armadura da un tunel de 6 m de radio y todas las holguras salen
    multiplicadas por 100.  El mundo es el unico espacio donde esto son metros."""
    joints = []
    normals = []
    for f in DJ_FINGERS:
        pts = [head_world(arm, n) for n in chain(side, f)]
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
    ref = (head_world(arm, "f_index.01.%s" % side)
           - head_world(arm, "f_pinky.01.%s" % side))
    if axis.dot(ref) < 0.0:
        axis = -axis
    return frame_matrix(center, axis, palm_normal(arm, side))


# ===========================================================================
# muestreo del donante: la pose, relativa a SU pistola, fotograma a fotograma
# ===========================================================================
def load_donor(donor: Path) -> tuple:
    reset_scene()
    objs = import_gltf(donor)
    arm = next(o for o in objs if o.type == "ARMATURE")
    meshes = [o for o in objs if o.type == "MESH"
              and any(m.type == "ARMATURE" for m in o.modifiers)]
    assert len(meshes) == 1, "BUILD ABORTA: %d mallas skinned (se esperaba 1)" % len(meshes)
    mesh = meshes[0]
    gun = next((o for o in objs if o.name == "pistol"), None)
    assert gun is not None, "BUILD ABORTA: el donante no trae el nodo `pistol`"
    print("BUILD donante:", donor.name, "| armadura", arm.name, "| malla", mesh.name,
          "| nodo pistola", gun.name)
    return arm, mesh, gun


def strip_donor(arm, mesh, gun, world: Matrix) -> None:
    """Deja SOLO la armadura, la malla de brazos y el nodo de la pistola (que
    hace falta para medir el movimiento del arma del donante)."""
    keep = {arm, mesh, gun}
    for obj in list(bpy.data.objects):
        if obj not in keep and obj.parent is not None and obj.parent not in keep:
            continue
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or obj is mesh:
            continue
        print("BUILD fuera malla ajena:", obj.name)
        bpy.data.objects.remove(obj, do_unlink=True)
    arm.parent = None
    arm.matrix_world = world.copy()
    arm.matrix_parent_inverse = Matrix.Identity(4)
    mesh.parent = arm
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    update()


def rename_bones(arm, mesh) -> None:
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
    for vg in mesh.vertex_groups:
        if vg.name in mapping:
            vg.name = mapping[vg.name]
    print("BUILD huesos: %d (deform %d)" % (
        len(arm.data.bones), sum(1 for b in arm.data.bones if b.use_deform)))


def drop_extra_uvs(mesh) -> None:
    while len(mesh.data.uv_layers) > 1:
        n = mesh.data.uv_layers[-1].name
        mesh.data.uv_layers.remove(mesh.data.uv_layers[-1])
        print("BUILD fuera capa UV:", n)


def sample_source(arm, gun, frames: list) -> dict:
    """Fotografia la pose del donante RELATIVA A SU PISTOLA en cada fotograma.

    El donante anima la pistola por su cuenta (se ladea, se le mueve la corredera)
    y los brazos por la suya: son objetos independientes.  Lo que sirve para
    NUESTRO juego es la pose de los brazos RELATIVA al arma, porque en runtime el
    arma la mueve `Glock.gd` y los brazos cuelgan de `BodyGive`.  Por eso se
    divide por la matriz del nodo `pistol` en cada fotograma."""
    scene = bpy.context.scene
    out = {}
    for f in sorted(set(frames)):
        scene.frame_set(f)
        update()
        g = gun.matrix_world.copy()
        gi = g.inverted()
        out[f] = {pb.name: gi @ (arm.matrix_world @ pb.matrix) for pb in arm.pose.bones}
    print("BUILD donante muestreado: %d fotogramas x %d huesos"
          % (len(out), len(next(iter(out.values())))))
    return out


def shorten_bone_tails(arm) -> None:
    """El donante trae longitudes de hueso a x100 (hasta 34 m).  La longitud no
    afecta al skinning (solo importan cabeza, orientacion y roll), pero deja el
    esqueleto legible y evita colas absurdas en el GLB."""
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm.data.edit_bones
    for b in arm.data.bones:
        if len(b.children) != 1:
            continue
        ch = b.children[0]
        d = (ch.head_local - b.head_local).length
        if d > 1e-4:
            e = ebs[b.name]
            z = e.z_axis.copy()
            e.tail = e.head + (e.tail - e.head).normalized() * d
            e.align_roll(z)
    bpy.ops.object.mode_set(mode="OBJECT")
    update()


def apply_targets(arm, targets: dict) -> None:
    """Escribe TODOS los huesos, padres antes que hijos."""
    order = []
    stack = [b for b in arm.data.bones if b.parent is None]
    while stack:
        b = stack.pop(0)
        order.append(b.name)
        stack += list(b.children)
    for name in order:
        m = targets.get(name)
        if m is None:
            continue
        pb = arm.pose.bones[name]
        pb.rotation_mode = "QUATERNION"
        pb.matrix = m
    update()



# ===========================================================================
# colocacion RIGIDA sobre NUESTRA Glock (nada de hundir la malla)
# ===========================================================================
def _cost_of(gaps: dict) -> float:
    """Coste del ajuste, con el criterio del dueño: LA MANO SE POSA, NO SE EMPUJA.

    Se busca AIRE PEQUEÑO Y POSITIVO (0 a +2 mm), no contacto.  Un dedo a 1 mm
    del lomo delantero no se ve; un dedo hundido 0,3 mm en el arma es una
    deformacion que se ve.  Penetracion 40:1; el aire solo se prefiere pequeño
    (0,05:1) para que el minimo caiga justo por fuera de la superficie.  La
    palma no entra: se apoya donde la deje la pose."""
    def cost(g):
        return 40.0 * (-g) if g < 0.0 else 0.05 * g

    return (cost(gaps["f_middle"]) + cost(gaps["f_ring"]) + cost(gaps["f_pinky"])
            + 2.0 * max(0.0, -gaps["f_index"]))


def _gaps_for(arm, mesh, base: dict, bvh: BVHTree, pads: dict, s0: Matrix,
              combos: list) -> list:
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


def fit_placement(arm, mesh, base: dict, bvh: BVHTree, F_world: Matrix) -> tuple:
    """Busca SOLO el desplazamiento y el giro de la boca: la pose la trae el
    donante, no se toca."""
    s0 = frame_matrix(GRIP_CENTER, GRIP_AXIS, GRIP_PALM["R"])
    pads = pad_points(arm, [mesh], base, "R", F_world)
    best = None

    def consider(combos, tag):
        nonlocal best
        for gaps, dloc, roll in _gaps_for(arm, mesh, base, bvh, pads, s0, combos):
            score = _cost_of(gaps)
            if best is None or score < best["score"]:
                best = {"score": score, "dloc": dloc, "roll": roll, "gaps": gaps}
        print("BUILD ajuste %-6s -> score=%.4f  holguras(mm) medio=%+.2f anular=%+.2f "
              "menique=%+.2f indice=%+.2f palma=%+.2f"
              % (tag, best["score"], 1000 * best["gaps"]["f_middle"],
                 1000 * best["gaps"]["f_ring"], 1000 * best["gaps"]["f_pinky"],
                 1000 * best["gaps"]["f_index"], 1000 * best["gaps"]["palm"]))

    consider([(Vector((dx, 0.0, dz)), roll)
              for dz in (0.020, 0.012, 0.004, -0.004, -0.012, -0.020)
              for dx in (-0.014, -0.006, 0.002, 0.010)
              for roll in (-24.0, -12.0, 0.0, 12.0, 24.0)], "grueso")
    bd, br = best["dloc"], best["roll"]
    consider([(bd + Vector((dx, 0.0, dz)), br + roll)
              for dz in (-0.004, 0.0, 0.004)
              for dx in (-0.003, 0.0, 0.003)
              for roll in (-6.0, 0.0, 6.0)], "fino")
    ## La MISMA composicion que usa la medida de holguras: s0 @ (rot @ c + dloc).
    ## Reconstruirla al reves (rotar despues de trasladar) colocaba la mano en
    ## otro sitio y el informe no cuadraba con el ajuste.
    m = s0 @ Matrix.Translation(best["dloc"]) @ Matrix.Rotation(math.radians(best["roll"]), 4, "Y")
    print("BUILD ajuste: dloc=%s roll=%+.0f score=%.4f (la pose NO se busca: viene del donante)"
          % ([round(v, 4) for v in best["dloc"]], best["roll"], best["score"]))
    return m, best


def grip_report(arm, mesh, base: dict, bvh: BVHTree, F_world: Matrix, socket: Matrix) -> None:
    """Informe por pieza de la holgura a la superficie del arma (mm).

    `socket` es la boca YA AJUSTADA (con su desplazamiento y giro): usar la boca
    nominal daria un informe que no cuadra con el ajuste."""
    pads = pad_points(arm, [mesh], base, "R", F_world)
    s0 = socket
    print("BUILD informe de agarre (R), holgura a la superficie del arma:")
    for key in ("f_index", "f_middle", "f_ring", "f_pinky", "thumb", "palm"):
        if key not in pads:
            continue
        vals = [(surf_gap(bvh, s0 @ c), c) for c in pads[key]]
        g, worst = min(vals, key=lambda t: t[0])
        print("   %-9s %+7.2f mm  (%3d puntos)" % (key, 1000.0 * g, len(pads[key])))


# ===========================================================================
# clips
# ===========================================================================
## Ventanas del donante (fotogramas de `allanimations`) para cada gesto.  Es una
## LECTURA del strip, no una etiqueta del autor: el donante trae una sola tira de
## 211 fotogramas con el disparo y las dos recargas, sin nombres.  Se midio la
## distancia mano izquierda-mano derecha para localizar los cuatro tramos en que
## la izquierda se suelta del arma (~20-40, ~76-100, ~125-148, ~150-192) y se
## miraron fotogramas sueltos.  Lo que NO esta verificado es que el asiento del
## cargador caiga en nuestro hito de 1,40 s: el donante lo hace a su ritmo.
WINDOWS = {"Reload": (16, 104), "ReloadEmpty": (104, 192), "Inspect": (40, 120)}
CLIPS = {"Idle": 3.00, "Fire": 0.26, "Reload": 2.10, "ReloadEmpty": 2.35, "Inspect": 2.00}


def clip_targets(A: dict, frame: int, Tg: Matrix, extra_root: Matrix | None) -> dict:
    T = b_mat(Tg)
    out = {name: T @ A[frame][name] for name in A[frame]}
    if extra_root is not None:
        out["root"] = extra_root @ out["root"]
    return out


def breath_matrix(amount: float) -> Matrix:
    return (Matrix.Rotation(math.radians(0.35 * amount), 4, Vector((1.0, 0.0, 0.0)))
            @ Matrix.Rotation(math.radians(0.25 * amount), 4, Vector((0.0, 0.0, 1.0))))


def twitch_matrix(kick: float) -> Matrix:
    m = Matrix.Rotation(math.radians(1.6 * kick), 4, Vector((1.0, 0.0, 0.0)))
    m.translation = Vector((0.0, 0.0016 * kick, 0.0022 * kick))
    return m


def warp(name: str, t: float) -> int:
    if name in ("Idle", "Fire"):
        return 0
    f0, f1 = WINDOWS[name]
    d = CLIPS[name]
    return int(round(f0 + (f1 - f0) * min(max(t / d, 0.0), 1.0)))


# ===========================================================================
# verificacion del GLB: se PARSEA el fichero, no se le pregunta a Blender
# ===========================================================================
TRI_MIN, TRI_MAX = 4000, 24000
BONE_MIN, BONE_MAX = 30, 60


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
    print("  meshes    :", [m.get("name") for m in meshes], "prims:", len(prims), "tris:", tris)
    if not (1 <= len(meshes) <= 2):
        bad("numero de mallas fuera de 1-2")
    if not (TRI_MIN <= tris <= TRI_MAX):
        bad("triangulos fuera de [%d, %d]" % (TRI_MIN, TRI_MAX))
    for name, p in prims:
        acc = gltf["accessors"][p["attributes"]["POSITION"]]
        print("    %-22s verts=%d min=%s max=%s" % (
            name, acc["count"], [round(v, 3) for v in acc["min"]],
            [round(v, 3) for v in acc["max"]]))
    mats = gltf.get("materials", [])
    print("  materiales:", [m.get("name") for m in mats])
    if not (1 <= len(mats) <= 2):
        bad("numero de materiales fuera de 1-2")
    for im in gltf.get("images", []):
        bv = gltf["bufferViews"][im["bufferView"]]
        start = bv.get("byteOffset", 0)
        w, h = png_size(blob_all[start:start + bv["byteLength"]])
        print("  imagen    : %-30s %dx%d bytes=%d mime=%s"
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
    end = [j for j in joints if "_end" in j]
    print("  huesos    :", len(joints), "| hojas _end:", end or "ninguna")
    if end:
        bad("quedan huesos hoja _end")
    if not (BONE_MIN <= len(joints) <= BONE_MAX):
        bad("numero de huesos fuera de [%d, %d]" % (BONE_MIN, BONE_MAX))
    for a in gltf.get("animations", []):
        tmax = max(gltf["accessors"][s["input"]]["max"][0] for s in a["samplers"])
        want = CLIPS.get(a["name"])
        flag = "" if want is not None and abs(tmax - want) < 1e-3 else "  <-- MAL"
        print("  clip %-12s dur=%.4f s (objetivo %s) canales=%d%s"
              % (a["name"], tmax, want, len(a["channels"]), flag))
        if want is None or abs(tmax - want) >= 1e-3:
            bad("clip %s con duracion %.4f" % (a["name"], tmax))
    names = sorted(a["name"] for a in gltf.get("animations", []))
    if names != sorted(CLIPS):
        bad("los clips no son exactamente %s" % sorted(CLIPS))
    print("  nombres   :", names)
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
    p.add_argument("--grip-report", type=int, default=0)
    p.add_argument("--verify", type=int, default=0)
    p.add_argument("--verify-only", default="")
    p.add_argument("--tex", type=int, default=1024)
    p.add_argument("--grip-slide", type=float, default=0.0)
    p.add_argument("--grip-off", default="0,0,0")
    return p.parse_args(argv)


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
            "  Es CC-BY-4.0 de DJMaesen, 'animated pistol',\n"
            "  https://sketchfab.com/3d-models/animated-pistol-bd896167e7ca44f19597d3afe6a8d83f\n"
            "  y NO esta en el repo (downloads/ es gitignored).  Descomprime el ZIP en\n"
            "  downloads/models/djmaesen_animated_pistol/extracted/." % donor)

    global GRIP_CENTER, GRIP_AXIS
    GRIP_CENTER = GRIP_CENTER + GRIP_AXIS * args.grip_slide \
        + Vector([float(v) for v in args.grip_off.split(",")])

    arm, mesh, gun = load_donor(donor)
    world = arm.matrix_world.copy()
    strip_donor(arm, mesh, gun, world)
    rename_bones(arm, mesh)
    drop_extra_uvs(mesh)

    # --- la pose la trae el donante, relativa a SU pistola -------------------
    act = max(bpy.data.actions, key=lambda a: len(a.fcurves))
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    print("BUILD accion del donante: %s  frames %d..%d  curvas=%d"
          % (act.name, f0, f1, len(act.fcurves)))
    A = sample_source(arm, gun, list(range(f0, f1 + 1)))
    bpy.context.scene.frame_set(f0)
    update()
    ## `fist_frame` devuelve el marco en espacio de ARMADURA: ahi viven la pose y
    ## la malla del donante (las dos al mismo factor), asi que es el unico sitio
    ## donde `pad_points` puede medir.  El mundo se obtiene aplicando la matriz
    ## del objeto, que NO se toca hasta despues de hornear.
    F_world = fist_frame(arm, "R")
    g0 = gun.matrix_world.copy()
    print("BUILD tunel del donante (mundo) centro=%s radio=%.4f m"
          % ([round(x, 4) for x in F_world.translation],
             max((head_world(arm, n) - F_world.translation).length
                 for f in DJ_FINGERS for n in chain("R", f))))
    # --- colocacion rigida sobre NUESTRA Glock ------------------------------
    ## El ajuste se mide con la POSE CRUDA del donante (la accion sigue puesta):
    ## es la unica consistente con su reposo, que es lo que usa `pad_points`.
    bvh = gun_grip_bvh()
    base = {b.name: b.matrix_local.copy() for b in arm.data.bones}
    bpy.context.scene.frame_set(f0)
    update()
    s0c, best = fit_placement(arm, mesh, base, bvh, F_world)
    if args.grip_report:
        grip_report(arm, mesh, base, bvh, F_world, s0c)
    ## Ahora si se suelta la accion: si siguiera puesta, cada `frame_set`/`update`
    ## reescribiria la pose que acabamos de componer.
    arm.animation_data.action = None
    reset_pose(arm)
    F_local = g0.inverted() @ F_world
    Tg = s0c @ F_local.inverted()

    # --- bind = Idle t=0 ----------------------------------------------------
    bind = clip_targets(A, f0, Tg, breath_matrix(0.0))
    bake_bind(arm, [mesh], bind)
    ## AHORA si: con la malla y el reposo ya metricos, los objetos a identidad.
    ## El donante trae la armadura y la malla a 0.01 y los huesos a x100; hornear
    ## el bind lo deja todo en metros, y limpiar el transform del objeto es lo
    ## que hace que el nodo raiz del GLB salga en IDENTIDAD.
    for obj in (arm, mesh):
        obj.parent = None if obj is arm else arm
        obj.matrix_basis = Matrix.Identity(4)
        obj.matrix_parent_inverse = Matrix.Identity(4)
    update()
    shorten_bone_tails(arm)

    # --- clips --------------------------------------------------------------
    if not args.bind_only:
        if arm.animation_data is None:
            arm.animation_data_create()
        for old in list(bpy.data.actions):
            bpy.data.actions.remove(old)
        for name in ("Idle", "Fire", "Reload", "ReloadEmpty", "Inspect"):
            dur = CLIPS[name]
            act_new = bpy.data.actions.new(name)
            act_new.use_fake_user = True
            arm.animation_data.action = act_new
            n = int(round(dur * FPS))
            for f in range(n + 1):
                t = f / FPS
                if name == "Idle":
                    extra = breath_matrix(math.sin(2.0 * math.pi * t / dur))
                elif name == "Fire":
                    kick = 0.0
                    ks = [(0.000, 0.0), (0.018, 0.15), (0.055, 1.0), (0.100, 0.55),
                          (0.150, -0.10), (0.200, 0.03), (0.260, 0.0)]
                    for i in range(len(ks) - 1):
                        if ks[i][0] <= t <= ks[i + 1][0]:
                            k = (t - ks[i][0]) / (ks[i + 1][0] - ks[i][0])
                            kick = ks[i][1] + (ks[i + 1][1] - ks[i][1]) * (k * k * (3 - 2 * k))
                            break
                    extra = twitch_matrix(kick)
                else:
                    extra = breath_matrix(0.25 * math.sin(2.0 * math.pi * t / dur))
                apply_targets(arm, clip_targets(A, warp(name, t), Tg, extra))
                for pb in arm.pose.bones:
                    pb.keyframe_insert("location", frame=f, group=pb.name)
                    pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            for fc in act_new.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = "LINEAR"
            print("BUILD clip %-12s %d frames (%.2f s) curvas=%d"
                  % (name, n + 1, dur, len(act_new.fcurves)))
        arm.animation_data.action = bpy.data.actions["Idle"]

    ad = arm.animation_data
    if ad is not None:
        for track in list(ad.nla_tracks):
            print("BUILD fuera pista NLA:", track.name)
            ad.nla_tracks.remove(track)

    # --- fuera la pistola del donante y sus nodos ---------------------------
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" or obj is arm:
            continue
        if obj.type in ("EMPTY",):
            print("BUILD fuera nodo del donante:", obj.name)
            bpy.data.objects.remove(obj, do_unlink=True)

    if args.tex > 0:
        for img in bpy.data.images:
            if img.size[0] and max(img.size) > args.tex:
                print("BUILD textura %s %s -> %d" % (img.name, tuple(img.size), args.tex))
                img.scale(args.tex, args.tex)

    arm.name = "ArmsRig"
    arm.data.name = "ArmsRig"
    mesh.name = "Arms_DJ"
    out.parent.mkdir(parents=True, exist_ok=True)
    activate(arm)
    bpy.ops.export_scene.gltf(
        filepath=str(out), export_format="GLB", use_selection=False, export_apply=False,
        export_animations=not args.bind_only, export_animation_mode="ACTIONS",
        export_nla_strips=False, export_frame_range=False, export_force_sampling=True,
        export_frame_step=1, export_bake_animation=False, export_skins=True,
        export_yup=True, export_image_format="AUTO",
        export_optimize_animation_size=False, export_anim_single_armature=True,
        export_influence_nb=4)
    print("BUILD escrito: %s (%.1f KB)" % (out, out.stat().st_size / 1024.0))
    if args.verify:
        verify(out)


if __name__ == "__main__":
    main()
