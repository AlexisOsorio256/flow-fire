"""Construye la mano derecha riggeada minima de FlowFire (v1: agarre horneado).

Reemplaza el blob procedural de 0 huesos por un rig de produccion minimo:
~20 deform bones, 1 mesh, 1 material, pose de agarre horneada sobre el Grip
de NUESTRA G19. Sin IK runtime, sin controllers, sin constraints: Godot recibe
ArmsRig limpio con clips por venir (Idle->Fire->ReloadEmpty->Reload->Inspect).

Uso:
    blender --background --python tools/build_hand_rig.py

La geometria son capsulas rigidas por falange (un grupo de vertices por hueso,
peso 1.0): el dedo no se dobla como plastilina, articula como guante. La pose
de agarre va horneada en los edit bones + malla, asi sin AnimationPlayer la
mano ya agarra. El donante historico (arms.glb 78 huesos, 5 clips Desert Eagle)
queda como museo: sus curvas serviran para retarget de Fire/Reload en la
siguiente iteracion, no aqui.
"""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector

REPO = Path(__file__).resolve().parents[1]
MODELS = REPO / "assets" / "models"


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def flat_material(name: str, color, metallic=0.0, roughness=0.9):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return mat


def add_capsule(name: str, location, scale, material, bone_name: str):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=12, ring_count=8, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    # Grupo rigido al hueso: un vertice, un hueso, peso 1.
    grp = obj.vertex_groups.new(name=bone_name)
    grp.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    return obj


def build() -> None:
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(MODELS / "g19_pistol.glb"))
    grip = bpy.data.objects.get("Grip")
    if grip is None:
        raise RuntimeError("g19_pistol.glb has no Grip socket")
    gp = grip.matrix_world.translation.copy()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    root = bpy.data.objects.new("RightHand", None)
    bpy.context.collection.objects.link(root)

    glove = flat_material("RightHand_Glove", (0.020, 0.024, 0.030),
                          metallic=0.0, roughness=0.9)

    # --- Armadura minima: antebrazo + muneca + palma + 4x3 dedos + pulgar x3
    #     + 2 helpers de palma = 20 deform bones. Solo lado derecho, solo mano.
    #     Nombres estables para la siguiente IA (clips por venir).
    bones: dict[str, tuple[Vector, Vector]] = {}
    bones["Forearm"] = (gp + Vector((0.010, -0.100, -0.095)),
                        gp + Vector((0.010, -0.045, -0.070)))
    bones["Wrist"] = (gp + Vector((0.010, -0.045, -0.070)),
                      gp + Vector((0.010, -0.005, -0.040)))
    bones["Palm"] = (gp + Vector((0.010, -0.005, -0.040)),
                     gp + Vector((0.010, 0.022, -0.028)))
    bones["PalmHelper"] = (gp + Vector((0.010, 0.000, -0.020)),
                           gp + Vector((0.010, 0.018, -0.018)))
    bones["WristTwist"] = (gp + Vector((0.010, -0.070, -0.080)),
                         gp + Vector((0.010, -0.030, -0.060)))
    finger_x = {"Index": -0.018, "Middle": -0.006, "Ring": 0.006, "Pinky": 0.018}
    for fname, x in finger_x.items():
        bones[f"{fname}Prox"] = (gp + Vector((x, 0.024, -0.030)),
                                 gp + Vector((x, 0.010, -0.043)))
        bones[f"{fname}Mid"] = (gp + Vector((x, 0.010, -0.043)),
                                gp + Vector((x, -0.002, -0.045)))
        bones[f"{fname}Dist"] = (gp + Vector((x, -0.002, -0.045)),
                                 gp + Vector((x, -0.011, -0.036)))
    bones["ThumbProx"] = (gp + Vector((-0.026, 0.014, -0.022)),
                          gp + Vector((-0.030, 0.006, -0.010)))
    bones["ThumbMid"] = (gp + Vector((-0.030, 0.006, -0.010)),
                         gp + Vector((-0.031, -0.001, 0.001)))
    bones["ThumbDist"] = (gp + Vector((-0.031, -0.001, 0.001)),
                          gp + Vector((-0.030, -0.007, 0.009)))
    assert 20 <= len(bones) <= 40, f"rig fuera de contrato 20-40: {len(bones)}"

    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm_obj = bpy.context.object
    arm_obj.name = "ArmsRig"
    arm = arm_obj.data
    arm.name = "ArmsRig"
    # El armature_add trae un hueso por defecto: se reutiliza como Forearm.
    edit_bones = arm.edit_bones
    default = edit_bones[0]
    default.name = "Forearm"
    default.head, default.tail = bones["Forearm"]
    for bname, (head, tail) in bones.items():
        if bname == "Forearm":
            continue
        eb = edit_bones.new(bname)
        eb.head, eb.tail = head, tail
    # Cadena: antebrazo > muneca > palma > dedos; pulgar cuelga de palma.
    edit_bones["Wrist"].parent = edit_bones["Forearm"]
    edit_bones["Palm"].parent = edit_bones["Wrist"]
    edit_bones["PalmHelper"].parent = edit_bones["Palm"]
    edit_bones["WristTwist"].parent = edit_bones["Forearm"]
    for fname in finger_x:
        edit_bones[f"{fname}Prox"].parent = edit_bones["Palm"]
        edit_bones[f"{fname}Mid"].parent = edit_bones[f"{fname}Prox"]
        edit_bones[f"{fname}Dist"].parent = edit_bones[f"{fname}Mid"]
    for t in ("ThumbProx", "ThumbMid", "ThumbDist"):
        pass
    edit_bones["ThumbProx"].parent = edit_bones["Palm"]
    edit_bones["ThumbMid"].parent = edit_bones["ThumbProx"]
    edit_bones["ThumbDist"].parent = edit_bones["ThumbMid"]
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_obj.parent = root
    arm_obj.matrix_parent_inverse = root.matrix_world.inverted()

    # --- Malla: una sola, 1 material, cada pieza rigidamente a su hueso.
    pieces = []
    pieces.append(add_capsule("PalmMesh", gp + Vector((0.010, 0.006, -0.024)),
                              (0.032, 0.038, 0.058), glove, "Palm"))
    pieces.append(add_capsule("PalmHelperMesh", gp + Vector((0.010, 0.008, -0.018)),
                              (0.030, 0.020, 0.040), glove, "PalmHelper"))
    pieces.append(add_capsule("ForearmMesh", gp + Vector((0.010, -0.070, -0.085)),
                              (0.036, 0.044, 0.070), glove, "Forearm"))
    pieces.append(add_capsule("WristMesh", gp + Vector((0.010, -0.025, -0.055)),
                              (0.032, 0.030, 0.045), glove, "Wrist"))
    pieces.append(add_capsule("CuffMesh", gp + Vector((0.010, -0.042, -0.135)),
                              (0.044, 0.050, 0.024), glove, "Forearm"))
    seg_scale = {"Prox": (0.0095, 0.013, 0.011), "Mid": (0.0085, 0.011, 0.010),
                 "Dist": (0.0075, 0.009, 0.009)}
    seg_off = {"Prox": (0.0, 0.017, -0.036), "Mid": (0.0, 0.004, -0.044),
               "Dist": (0.0, -0.006, -0.040)}
    for fname, x in finger_x.items():
        for seg in ("Prox", "Mid", "Dist"):
            dx, dy, dz = seg_off[seg]
            pieces.append(add_capsule(
                f"{fname}{seg}Mesh", gp + Vector((x + dx, dy, dz)),
                seg_scale[seg], glove, f"{fname}{seg}"))
    thumb_off = {"ThumbProx": (-0.028, 0.010, -0.016),
                 "ThumbMid": (-0.030, 0.002, -0.004),
                 "ThumbDist": (-0.030, -0.004, 0.005)}
    for tname, (ox, oy, oz) in thumb_off.items():
        pieces.append(add_capsule(
            f"{tname}Mesh", gp + Vector((ox, oy, oz)),
            (0.011, 0.014, 0.012), glove, tname))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    hand = bpy.context.object
    hand.name = "RightHandMesh"
    hand.parent = root
    hand.matrix_parent_inverse = root.matrix_world.inverted()
    # Modifier de armadura: los grupos ya existen con los nombres de hueso.
    mod = hand.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj

    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.select_all(action="DESELECT")
    hand.select_set(True)
    bpy.context.view_layer.objects.active = hand
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    # --- Clips horneados v1: Idle (agarre, 1 s loop) + Fire (latigazo 0,2 s).
    #     ReloadEmpty/Reload/Inspect vienen por retarget del donante historico.
    #     La pose de reposo YA es el agarre, asi los clips solo animan el gesto
    #     sobre ella (sin IK, sin constraints: todo keyframes a mano).
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    pose_bones = arm_obj.pose.bones
    for pb in pose_bones:
        pb.rotation_mode = "XYZ"
    scene = bpy.context.scene
    scene.render.fps = 60
    # Idle: 60 frames estatico (el agarre respira via codigo BodyGive, no aqui).
    idle = bpy.data.actions.new("Idle")
    arm_obj.animation_data_create()
    arm_obj.animation_data.action = idle
    for pb in pose_bones:
        pb.keyframe_insert(data_path="rotation_euler", frame=0)
        pb.keyframe_insert(data_path="location", frame=0)
        pb.keyframe_insert(data_path="rotation_euler", frame=60)
        pb.keyframe_insert(data_path="location", frame=60)
    idle.use_cyclic = True
    # Fire: latigazo de muneca a 2 frames (~33 ms, con el kick) y vuelta a 12.
    fire = bpy.data.actions.new("Fire")
    arm_obj.animation_data.action = fire
    for pb in pose_bones:
        pb.keyframe_insert(data_path="rotation_euler", frame=0)
        pb.keyframe_insert(data_path="location", frame=0)
    pose_bones["Wrist"].rotation_euler = (0.06, 0.0, 0.0)
    pose_bones["Palm"].rotation_euler = (0.04, 0.0, 0.0)
    for fname in ("Index", "Middle", "Ring", "Pinky"):
        pose_bones[f"{fname}Prox"].rotation_euler = (0.05, 0.0, 0.0)
    pose_bones["Wrist"].keyframe_insert(data_path="rotation_euler", frame=2)
    pose_bones["Palm"].keyframe_insert(data_path="rotation_euler", frame=2)
    for fname in ("Index", "Middle", "Ring", "Pinky"):
        pose_bones[f"{fname}Prox"].keyframe_insert(data_path="rotation_euler", frame=2)
    for pb in pose_bones:
        pb.keyframe_insert(data_path="rotation_euler", frame=12)
    for pb in pose_bones:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.keyframe_insert(data_path="rotation_euler", frame=0)
    # Stash a NLA para que el exportador glTF los incluya como clips.
    arm_obj.animation_data.action = None
    for act in (idle, fire):
        track = arm_obj.animation_data.nla_tracks.new()
        track.name = act.name
        strip = track.strips.new(act.name, 0, act)
        strip.blend_type = "REPLACE"
    bpy.ops.object.mode_set(mode="OBJECT")

    hand["asset_role"] = "rigged right hand, baked grip, Idle+Fire baked"
    hand["bones"] = len(bones)
    hand["animations"] = 2
    hand["material_count"] = 1
    triangles = sum(max(0, len(p.vertices) - 2) for p in hand.data.polygons)
    hand["approx_triangles"] = triangles
    print("hand bones", len(bones), "triangles", triangles)
    if not 20 <= len(bones) <= 40:
        raise RuntimeError(f"rig fuera de contrato 20-40: {len(bones)}")
    if not 2000 <= triangles <= 6000:
        raise RuntimeError(f"mano fuera de contrato 2-6k tris: {triangles}")

    # Exporta root (armadura + malla). El arma de referencia ya se borro:
    # este asset no puede convertirse en segunda fuente de Glock.
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    out = MODELS / "right_hand.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out), export_format="GLB", use_selection=True,
        export_apply=True, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_image_format="AUTO",
        export_skins=True)
    print("built", out, "bones", len(bones), "triangles", triangles)


if __name__ == "__main__":
    build()
