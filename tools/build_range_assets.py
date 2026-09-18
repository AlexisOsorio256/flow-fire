"""Build the two small, source-controlled Blender assets used by FlowFire.

The script deliberately owns only presentation geometry:

* ``range_shell.glb`` is the fixed architecture and its visual luminaires.
* ``right_hand.glb`` is a single, baked, bone-free right hand that shares the
  weapon coordinate space.  It is not allowed to contain weapon geometry.

Run from the repository root with Blender 4.x::

    blender --background --python tools/build_range_assets.py

The shell reuses the repository's CC0 PBR textures and embeds them in the GLB;
the hand uses one small procedural glove material and no texture.
"""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector


REPO = Path(__file__).resolve().parents[1]
MODELS = REPO / "assets" / "models"
TEXTURES = REPO / "assets" / "textures" / "real"


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        # Factory reset normally leaves these empty.  Removing orphaned data
        # makes repeated local builds deterministic as well.
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def image(path: Path, non_color: bool = False):
    img = bpy.data.images.load(str(path), check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def pbr_material(
    name: str,
    albedo_path: Path | None = None,
    roughness_path: Path | None = None,
    normal_path: Path | None = None,
    color=(0.8, 0.8, 0.8, 1.0),
    metallic: float = 0.0,
    roughness: float = 0.8,
    uv_scale=(1.0, 1.0, 1.0),
):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    if albedo_path is not None:
        coords = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = uv_scale
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image(albedo_path)
        links.new(coords.outputs["UV"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], shader.inputs["Base Color"])

    if roughness_path is not None:
        coords = nodes.get("Texture Coordinate") or nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = uv_scale
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image(roughness_path, non_color=True)
        links.new(coords.outputs["UV"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], shader.inputs["Roughness"])

    if normal_path is not None:
        coords = nodes.get("Texture Coordinate") or nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = uv_scale
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image(normal_path, non_color=True)
        normal = nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value = 0.65
        links.new(coords.outputs["UV"], mapping.inputs["Vector"])
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        links.new(tex.outputs["Color"], normal.inputs["Color"])
        links.new(normal.outputs["Normal"], shader.inputs["Normal"])

    return mat


def flat_material(name: str, color, metallic=0.0, roughness=0.8, emission=None):
    mat = pbr_material(name, color=(*color, 1.0), metallic=metallic, roughness=roughness)
    if emission is not None:
        shader = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
        shader.inputs["Emission Color"].default_value = (*emission, 1.0)
        shader.inputs["Emission Strength"].default_value = 2.5
    return mat


def add_box(name: str, location, size, material, bevel=0.018, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Real bevel", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def add_ellipsoid(name: str, location, scale, material):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=24,
        ring_count=12,
        radius=1.0,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def join_objects(name: str, objects, root):
    if not objects:
        raise RuntimeError(f"No geometry created for {name}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    joined.parent = root
    joined.matrix_parent_inverse = root.matrix_world.inverted()
    return joined


def export_root(root, path: Path):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )


def build_range_shell() -> None:
    reset_scene()
    root = bpy.data.objects.new("RangeShell", None)
    bpy.context.collection.objects.link(root)

    floor = pbr_material(
        "Range_Concrete_Floor",
        TEXTURES / "concrete_brushed_concrete_diff.jpg",
        TEXTURES / "concrete_brushed_concrete_rough.jpg",
        TEXTURES / "concrete_brushed_concrete_nor_gl.jpg",
        color=(0.86, 0.86, 0.86, 1.0),
        roughness=0.78,
        uv_scale=(6.0, 6.0, 6.0),
    )
    wall = pbr_material(
        "Range_Concrete_Wall",
        TEXTURES / "concrete_concrete_diff.jpg",
        TEXTURES / "concrete_concrete_rough.jpg",
        TEXTURES / "concrete_concrete_nor_gl.jpg",
        color=(0.72, 0.72, 0.74, 1.0),
        roughness=0.88,
        uv_scale=(3.0, 3.0, 3.0),
    )
    metal = pbr_material(
        "Range_Painted_Metal",
        TEXTURES / "metal_metal_plate_diff.jpg",
        TEXTURES / "metal_metal_plate_rough.jpg",
        TEXTURES / "metal_metal_plate_nor_gl.jpg",
        color=(0.28, 0.30, 0.33, 1.0),
        metallic=0.72,
        roughness=0.46,
        uv_scale=(2.0, 2.0, 2.0),
    )
    wood = pbr_material(
        "Range_Oak_Trim",
        TEXTURES / "wood_oak_wood_planks_diff.jpg",
        TEXTURES / "wood_oak_wood_planks_rough.jpg",
        TEXTURES / "wood_oak_wood_planks_nor_gl.jpg",
        color=(0.75, 0.62, 0.48, 1.0),
        roughness=0.82,
        uv_scale=(2.0, 2.0, 2.0),
    )
    light = flat_material("Range_Luminaire", (0.86, 0.84, 0.76), roughness=0.35, emission=(1.0, 0.92, 0.72))
    marking = flat_material("Range_Markings", (0.54, 0.49, 0.38), roughness=0.9)

    groups = {material: [] for material in [floor, wall, metal, wood, light, marking]}

    # Blender's +Y maps to Godot's -Z in the canonical GLB convention used by
    # the pistol.  The dimensions below therefore describe the Godot room while
    # the conversion to Blender Y is explicit at each call site.
    groups[floor].append(add_box("Floor slab", (0.0, 30.0, -0.15), (24.0, 72.0, 0.30), floor, 0.035))
    groups[wall].extend([
        add_box("Left wall", (-12.0, 30.0, 2.1), (0.30, 72.0, 4.2), wall, 0.035),
        add_box("Right wall", (12.0, 30.0, 2.1), (0.30, 72.0, 4.2), wall, 0.035),
        add_box("Front wall", (0.0, -6.0, 2.1), (24.0, 0.30, 4.2), wall, 0.035),
        add_box("Back wall", (0.0, 66.0, 2.1), (24.0, 0.30, 4.2), wall, 0.035),
        add_box("Ceiling", (0.0, 30.0, 4.2), (24.0, 72.0, 0.20), wall, 0.025),
    ])

    # Columns and overhead beams break the long box silhouette.  They are
    # architectural, not target geometry.
    for x in (-8.0, 8.0):
        for y in (10.0, 22.0, 34.0, 46.0, 58.0):
            groups[wall].append(add_box("Column", (x, y, 2.1), (0.50, 0.50, 4.2), wall, 0.045))
    for y in (4.0, 16.0, 28.0, 40.0, 52.0, 64.0):
        groups[metal].append(add_box("Roof beam", (0.0, y, 3.93), (23.3, 0.24, 0.30), metal, 0.035))

    # Low lane separators and service trims give the near field a built scale.
    for x in (-9.0, -3.0, 3.0, 9.0):
        groups[metal].append(add_box("Lane divider", (x, 0.5, 0.72), (0.08, 8.0, 1.35), metal, 0.025))
        groups[metal].append(add_box("Lane divider foot", (x, 0.5, 0.08), (0.40, 8.0, 0.12), metal, 0.018))
    groups[metal].extend([
        add_box("Left cable tray", (-11.55, 30.0, 3.10), (0.18, 72.0, 0.18), metal, 0.025),
        add_box("Right cable tray", (11.55, 30.0, 3.10), (0.18, 72.0, 0.18), metal, 0.025),
        add_box("Left baseboard", (-11.72, 30.0, 0.14), (0.12, 72.0, 0.28), metal, 0.018),
        add_box("Right baseboard", (11.72, 30.0, 0.14), (0.12, 72.0, 0.28), metal, 0.018),
    ])

    # A static stepped bullet trap silhouette at the end of the room.  Its
    # functional backstop collision remains a Godot body so RangeShell never
    # owns material/penetration metadata.
    for index, z in enumerate((0.40, 0.82, 1.24, 1.66, 2.08, 2.50)):
        groups[metal].append(add_box(
            "Bullet trap fin",
            (0.0, 63.45 - index * 0.045, z),
            (20.0, 0.10, 0.30),
            metal,
            0.018,
            rotation=(0.0, 0.0, -0.18),
        ))
    groups[wood].extend([
        add_box("Trap side", (-10.2, 63.4, 1.35), (0.25, 0.60, 2.7), wood, 0.025),
        add_box("Trap side", (10.2, 63.4, 1.35), (0.25, 0.60, 2.7), wood, 0.025),
    ])

    # Fixtures are geometry in the GLB; their actual light sources live in the
    # RangeShell scene where Godot can configure Mobile shadows cheaply.
    for y in (-2.0, 6.0, 18.0, 30.0, 42.0, 54.0):
        for x in (-5.0, 5.0):
            groups[metal].append(add_box("Luminaire housing", (x, y, 4.05), (1.7, 0.34, 0.06), metal, 0.025))
            groups[light].append(add_box("Luminaire diffuser", (x, y, 4.00), (1.55, 0.24, 0.035), light, 0.012))

    for godot_z in (-5.0, -10.0, -15.0, -25.0, -35.0, -50.0):
        groups[marking].append(add_box("Distance marking", (0.0, -godot_z, 0.006), (6.0, 0.09, 0.012), marking, 0.004))

    for material, objects in groups.items():
        if objects:
            join_objects(f"RangeShell_{material.name}", objects, root)

    root["asset_role"] = "static range presentation"
    root["functional_ballistics"] = False
    export_root(root, MODELS / "range_shell.glb")
    print("built", MODELS / "range_shell.glb")


def build_right_hand() -> None:
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=str(MODELS / "g19_pistol.glb"))
    grip = bpy.data.objects.get("Grip")
    if grip is None:
        raise RuntimeError("g19_pistol.glb has no Grip socket")
    grip_position = grip.matrix_world.translation.copy()

    # Remove the reference weapon before authoring the hand.  The asset is
    # intentionally a single mesh and cannot become a second weapon source.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    root = bpy.data.objects.new("RightHand", None)
    bpy.context.collection.objects.link(root)
    glove = flat_material("RightHand_Glove", (0.0001, 0.0002, 0.0003), metallic=0.0, roughness=0.94)
    glove_shader = next(node for node in glove.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    glove_shader.inputs["Specular IOR Level"].default_value = 0.24

    pieces = []
    # The local pose is authored around the measured Grip socket.  The palm
    # overlaps the grip, four short fingers wrap its front edge, and a separate
    # forearm/cuff keeps the silhouette readable without a rig or animation.
    pieces.append(add_ellipsoid(
        "Palm",
        grip_position + Vector((0.010, 0.004, -0.026)),
        (0.033, 0.041, 0.064),
        glove,
    ))
    pieces.append(add_ellipsoid(
        "Forearm",
        grip_position + Vector((0.010, -0.024, -0.090)),
        (0.037, 0.046, 0.074),
        glove,
    ))
    pieces.append(add_ellipsoid(
        "Cuff",
        grip_position + Vector((0.010, -0.042, -0.135)),
        (0.044, 0.050, 0.024),
        glove,
    ))
    for index, x in enumerate((-0.018, -0.006, 0.006, 0.018)):
        pieces.append(add_ellipsoid(
            f"Finger_{index + 1}",
            grip_position + Vector((x, 0.022, -0.039)),
            (0.010, 0.032, 0.014),
            glove,
        ))
    pieces.append(add_ellipsoid(
        "Thumb",
        grip_position + Vector((-0.026, 0.014, -0.014)),
        (0.018, 0.034, 0.016),
        glove,
    ))

    hand = join_objects("RightHand", pieces, root)
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.select_all(action="DESELECT")
    hand.select_set(True)
    bpy.context.view_layer.objects.active = hand
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    hand["asset_role"] = "baked right hand presentation"
    hand["bones"] = 0
    hand["animations"] = 0
    hand["material_count"] = 1
    triangles = sum(max(0, len(polygon.vertices) - 2) for polygon in hand.data.polygons)
    hand["approx_triangles"] = triangles
    if not 2000 <= triangles <= 5000:
        raise RuntimeError(f"right hand triangle contract failed: {triangles}")

    export_root(root, MODELS / "right_hand.glb")
    print("built", MODELS / "right_hand.glb", "triangles", triangles)


if __name__ == "__main__":
    build_range_shell()
    build_right_hand()
