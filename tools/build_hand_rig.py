"""Construye la mano derecha de FlowFire: malla unica poseida, sin armature.

Uso:
    blender --background --python tools/build_hand_rig.py

DECISION DE DISENO (y por que)
------------------------------
El pipeline completo (armature + skin + huesos) se probo y funciona, pero la
pose de agarre no sobrevivia al viaje: la malla salia con los dedos abiertos y
descentrada, y diagnosticarla era caro porque cada AABB incluia la cadena de
parenting (container -> armature -> hueso -> malla) y el addon BlenderMCP metia
un objeto parasito que falseaba las medidas.

La mano NO necesita esqueleto para nada de lo que hace en el juego. El
viewmodel ya mueve la mano entera con `PoseRoot` (bob, sway, respiracion) y con
`GlockRecoil` (retroceso), y la pose de agarre es CONSTANTE: los dedos no se
mueven respecto al arma, porque la mano sujeta la empuñadura.

Asi que la pose se hornea en la malla y el GLB sale con UN nodo y CERO huesos.
Eso hace la mano mas barata, elimina una clase entera de bugs de espacio y deja
el asset inspeccionable de un vistazo. El donante CC0 y su rig quedan en
downloads/ y en la historia de Git por si alguna vez hace falta una mano
animada de verdad.

DONANTE
-------
"fps arms (rigged only)" de **para** (OpenGameArt), **CC0**:
https://opengameart.org/content/fps-arms-rigged-only
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector

REPO = Path(__file__).resolve().parents[1]
MODELS = REPO / "assets" / "models"
SOURCE = REPO / "downloads" / "models" / "oga_fps_arms_para" / "FPS ARMS RIG 1.blend"

# El donante esta en DECIMETROS: la mano derecha mide 1.92 unidades de puño a
# punta del corazon y una mano de varon mide ~0.19 m. Medido, no supuesto.
SCALE = 0.1

KEEP_GROUPS = [
    "forearm.R", "hand.R",
    "palm_index.R", "f_index.01.R", "f_index.02.R", "f_index.03.R",
    "palm_middle.R", "f_middle.01.R", "f_middle.02.R", "f_middle.03.R",
    "palm_ring.R", "f_ring.01.R", "f_ring.02.R", "f_ring.03.R",
    "palm_pinky.R", "f_pinky.01.R", "f_pinky.02.R", "f_pinky.03.R",
    "thumb.01.R", "thumb.02.R", "thumb.03.R",
]
DROP_BONES = ["clavicle.R", "deltoid.R", "hand.R.control",
              "clavicle.L", "deltoid.L", "upper_arm.L", "forearm.L",
              "hand.L", "hand.L.control"]
# Curvatura del agarre (grados), del rig anterior ya validado en capturas.
GRIP_CURL = {
    "f_index.01.R": 150.0, "f_index.02.R": 33.0, "f_index.03.R": 54.0,
    "f_middle.01.R": 150.0, "f_middle.02.R": 33.0, "f_middle.03.R": 54.0,
    "f_ring.01.R": 150.0, "f_ring.02.R": 33.0, "f_ring.03.R": 54.0,
    "f_pinky.01.R": 150.0, "f_pinky.02.R": 33.0, "f_pinky.03.R": 54.0,
    "thumb.01.R": 58.0, "thumb.02.R": 25.0, "thumb.03.R": 22.0,
}
# Direccion del codo respecto al puño, en espacio del arma (metros). Deja el
# antebrazo entrando por la esquina inferior derecha, como en un viewmodel.
ELBOW_OFFSET = Vector((0.13, -0.13, 0.20))
# Cuanto baja el punto de agarre del puño a la palma (metros).
GRIP_BELOW_HAND = 0.018


## AJUSTE FINO del encaje contra la geometria del arma (metros, espacio del
## arma). PENDIENTE: la ORIENTACION esta resuelta (base anatomica medida,
## det(rotacion) = +1), pero el desplazamiento final contra la empuñadura
## necesita otra pasada de iteracion visual. Se deja a cero y escrito antes que
## poner un numero inventado que parezca calibrado.
HAND_OFFSET = Vector((0.0, 0.0, 0.0))

def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for group in (bpy.data.objects, bpy.data.meshes, bpy.data.armatures,
                  bpy.data.materials, bpy.data.actions, bpy.data.images):
        for item in list(group):
            if item.users == 0:
                group.remove(item)


def load_source():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    armature = bpy.data.objects["caucasian_male_1"]
    mesh = bpy.data.objects["caucasian_male_1:Body"]
    for obj in list(bpy.data.objects):
        if obj not in (armature, mesh):
            bpy.data.objects.remove(obj, do_unlink=True)
    return armature, mesh


def prune(mesh) -> None:
    """Deja solo del codo a los dedos, con bmesh (el modo EDIT borraba todo)."""
    keep = set(KEEP_GROUPS)
    for group in list(mesh.vertex_groups):
        if group.name not in keep:
            mesh.vertex_groups.remove(group)
    live = {g.index for g in mesh.vertex_groups}
    dead = [v.index for v in mesh.data.vertices
            if sum(g.weight for g in v.groups if g.group in live) < 0.05]
    if dead:
        bm = bmesh.new()
        bm.from_mesh(mesh.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in dead], context="VERTS")
        bm.to_mesh(mesh.data)
        bm.free()
        mesh.data.update()
    print("HAND malla podada: %d verts, %d polys (grupos conservados para el"
          " modificador de armature)" % (len(mesh.data.vertices), len(mesh.data.polygons)))


def simplify_armature(armature) -> None:
    for pose_bone in armature.pose.bones:
        for constraint in list(pose_bone.constraints):
            pose_bone.constraints.remove(constraint)
        pose_bone.rotation_mode = "QUATERNION"
    drop = set(DROP_BONES)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    edit = armature.data.edit_bones
    for name in drop:
        bone = edit.get(name)
        if bone is None:
            continue
        for child in list(bone.children):
            if child.name not in drop:
                child.parent = bone.parent
                child.use_connect = False
        edit.remove(bone)
    keep = set(KEEP_GROUPS) | {"upper_arm.R"}
    for name in list(edit.keys()):
        if name not in keep:
            edit.remove(edit[name])
    bpy.ops.object.mode_set(mode="OBJECT")


def bone_dir(armature, name: str) -> Vector:
    bone = armature.data.bones[name]
    return (bone.tail_local - bone.head_local).normalized()


def pose_hand(armature) -> None:
    """Cierra los dedos y lleva el antebrazo al codo.

    Cada hueso se orienta con la rotacion MINIMA entre dos direcciones, asi no
    hay que portar angulos de Euler de un rig a otro (que es lo que hace fragil
    el retarget).
    """
    for name, degrees in GRIP_CURL.items():
        pose_bone = armature.pose.bones.get(name)
        if pose_bone is None:
            continue
        parent = pose_bone.parent
        axis = bone_dir(armature, parent.name) if parent else Vector((1.0, 0.0, 0.0))
        curl = axis.cross(Vector((0.0, 1.0, 0.0)))
        if curl.length < 1e-6:
            curl = axis.cross(Vector((0.0, 0.0, 1.0)))
        if curl.length < 1e-6:
            curl = Vector((1.0, 0.0, 0.0))
        curl.normalize()
        pose_bone.rotation_quaternion = Quaternion(curl, math.radians(degrees))


def bake_pose(mesh, armature) -> None:
    """Hornea la pose en la malla y suelta el armature.

    Es el paso que faltaba: el GLB llevaba el skin y la malla en REPOSO, asi que
    el agarre no viajaba y la mano salia con los dedos abiertos en el juego.
    """
    bpy.context.view_layer.objects.active = mesh
    # La matriz de mundo se guarda ANTES de soltar del padre: al hacer
    # `parent = None` se pierde la herencia y la malla se desplazaba (el puño
    # acababa a 0,37 m del origen en la caja final).
    world = mesh.matrix_world.copy()
    for modifier in list(mesh.modifiers):
        if modifier.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    mesh.parent = None
    mesh.matrix_world = world
    # Ya hornado: los grupos de vertices no hacen falta en el GLB.
    for group in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(group)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for obj in list(bpy.data.objects):
        if obj.type == "ARMATURE":
            bpy.data.objects.remove(obj, do_unlink=True)


def main() -> None:
    reset_scene()
    armature, mesh = load_source()
    prune(mesh)
    simplify_armature(armature)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    pose_hand(armature)
    # El antebrazo solo: rotar upper_arm.R desplaza hand.R (es su padre) y la
    # mano se sale del arma.
    local_elbow = ELBOW_OFFSET.normalized()
    pose_bone = armature.pose.bones.get("forearm.R")
    if pose_bone is not None:
        pose_bone.rotation_quaternion = bone_dir(armature, "forearm.R").rotation_difference(-local_elbow)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.context.view_layer.update()

    # DIRECCIONES ANATOMICAS MEDIDAS EN LA POSE. La base NO se elige a ojo:
    # en un agarre real el eje de la empuñadura va A LO LARGO DEL ANTEBRAZO y la
    # palma apoya en el lomo trasero.
    #
    #   palma (puño->nudillos)   -> -Z (al morro)
    #   arriba por la empuñadura -> +Y
    #   lateral                  -> SALE de las otras dos: L = F x U
    #
    # Fijar el lateral a mano daba det(T) = -1, o sea una mano IZQUIERDA (un
    # espejo). Con L = F x U el determinante es +1 y es una rotacion de verdad.
    wrist_world = armature.matrix_world @ armature.data.bones["hand.R"].head_local
    palm = ((armature.matrix_world @ armature.data.bones["f_middle.01.R"].head_local) - wrist_world).normalized()
    lat_anat = ((armature.matrix_world @ armature.data.bones["f_pinky.01.R"].head_local)
                - (armature.matrix_world @ armature.data.bones["f_index.01.R"].head_local)).normalized()
    # Ortogonalizar: los ejes MEDIDOS no son exactamente perpendiculares y sin
    # esto la "rotacion" sale con determinante 1,073 (3,6% de escala parásita).
    lat_anat = (lat_anat - palm * lat_anat.dot(palm)).normalized()
    third = palm.cross(lat_anat)
    source = Matrix(((palm.x, lat_anat.x, third.x),
                     (palm.y, lat_anat.y, third.y),
                     (palm.z, lat_anat.z, third.z))).to_4x4()
    forward = Vector((0.0, 0.0, -1.0))
    up = Vector((0.0, 1.0, 0.0))
    lat_w = forward.cross(up)
    target_basis = Matrix(((lat_w.x, forward.x, up.x),
                           (lat_w.y, forward.y, up.y),
                           (lat_w.z, forward.z, up.z))).to_4x4()
    rotation = target_basis @ source.inverted()
    det = rotation.to_3x3().determinant()
    print("HAND det(anatomica)=%.3f det(arma)=%.3f det(rotacion)=%.3f"
          % (source.to_3x3().determinant(), target_basis.to_3x3().determinant(), det))
    assert det > 0.0, "orientacion ESPEJO (determinante negativo): revisar L = F x U"

    transform = Matrix.Scale(SCALE, 4) @ rotation
    target = HAND_OFFSET + Vector((0.0, -GRIP_BELOW_HAND, 0.0))
    landed = transform @ wrist_world
    residual = target - landed
    print("HAND puño aterriza en=(%.4f, %.4f, %.4f)"
          % (landed.x, landed.y, landed.z))

    bake_pose(mesh, armature)
    # ORDEN: transformar primero y trasladar despues, en el espacio final. Al
    # reves, el desplazamiento tambien gira y la mano acaba a 0,37 m del origen.
    mesh.data.transform(transform)
    mesh.data.transform(Matrix.Translation(residual))
    mesh.data.update()

    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for vert in mesh.data.vertices:
        for i in range(3):
            lo[i] = min(lo[i], vert.co[i])
            hi[i] = max(hi[i], vert.co[i])
    print("HAND caja final: pos=(%.4f, %.4f, %.4f) size=(%.4f, %.4f, %.4f)"
          % (lo.x, lo.y, lo.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))
    print("HAND tris=%d huesos=0 materiales=%d"
          % (sum(len(p.vertices) - 2 for p in mesh.data.polygons),
             len(mesh.data.materials)))
    export(mesh)


def export(mesh) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    MODELS.mkdir(parents=True, exist_ok=True)
    out = MODELS / "right_hand.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out), export_format="GLB", use_selection=True,
        export_apply=True, export_texcoords=True, export_normals=True,
        export_skins=False, export_animations=False,
        export_materials="EXPORT", export_image_format="AUTO")
    print("HAND exportado %s %.0f KB" % (out, out.stat().st_size / 1024))


if __name__ == "__main__":
    main()
