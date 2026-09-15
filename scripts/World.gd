extends Node3D

const CONCRETE_ALBEDO: Texture2D = preload("res://assets/textures/concrete_albedo.png")
const CONCRETE_NORMAL: Texture2D = preload("res://assets/textures/concrete_normal.png")
const CONCRETE_ROUGHNESS: Texture2D = preload("res://assets/textures/concrete_roughness.png")
const WOOD_ALBEDO: Texture2D = preload("res://assets/textures/wood_albedo.png")
const WOOD_NORMAL: Texture2D = preload("res://assets/textures/wood_normal.png")
const WOOD_ROUGHNESS: Texture2D = preload("res://assets/textures/wood_roughness.png")
const METAL_ALBEDO: Texture2D = preload("res://assets/textures/metal_albedo.png")
const METAL_ROUGHNESS: Texture2D = preload("res://assets/textures/metal_roughness.png")

var concrete_mat: StandardMaterial3D
var wall_mat: StandardMaterial3D
var ceiling_mat: StandardMaterial3D
var wood_mat: StandardMaterial3D
var metal_mat: StandardMaterial3D
var pillar_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D
var stand_mat: StandardMaterial3D


func build() -> void:
    _materials()
    _build_room()
    _build_props()
    _build_targets()
    _build_lights()


func _materials() -> void:
    concrete_mat = StandardMaterial3D.new()
    concrete_mat.albedo_texture = CONCRETE_ALBEDO
    concrete_mat.roughness_texture = CONCRETE_ROUGHNESS
    concrete_mat.normal_enabled = true
    concrete_mat.normal_texture = CONCRETE_NORMAL
    concrete_mat.normal_scale = 0.8
    concrete_mat.uv1_scale = Vector3(6, 8, 6)
    concrete_mat.roughness = 0.92

    wall_mat = StandardMaterial3D.new()
    wall_mat.albedo_texture = CONCRETE_ALBEDO
    wall_mat.roughness_texture = CONCRETE_ROUGHNESS
    wall_mat.normal_enabled = true
    wall_mat.normal_texture = CONCRETE_NORMAL
    wall_mat.normal_scale = 0.5
    wall_mat.albedo_color = Color(0.72, 0.72, 0.74)
    wall_mat.uv1_scale = Vector3(4, 2, 4)

    ceiling_mat = StandardMaterial3D.new()
    ceiling_mat.albedo_color = Color(0.15, 0.16, 0.17)
    ceiling_mat.roughness = 0.95

    wood_mat = StandardMaterial3D.new()
    wood_mat.albedo_texture = WOOD_ALBEDO
    wood_mat.roughness_texture = WOOD_ROUGHNESS
    wood_mat.normal_enabled = true
    wood_mat.normal_texture = WOOD_NORMAL
    wood_mat.normal_scale = 1.0
    wood_mat.uv1_scale = Vector3(1.5, 1, 1.5)
    wood_mat.roughness = 0.8

    metal_mat = StandardMaterial3D.new()
    metal_mat.albedo_texture = METAL_ALBEDO
    metal_mat.roughness_texture = METAL_ROUGHNESS
    metal_mat.metallic = 0.9
    metal_mat.roughness = 0.32
    metal_mat.uv1_scale = Vector3(2, 2, 2)

    pillar_mat = StandardMaterial3D.new()
    pillar_mat.albedo_texture = CONCRETE_ALBEDO
    pillar_mat.roughness_texture = CONCRETE_ROUGHNESS
    pillar_mat.normal_enabled = true
    pillar_mat.normal_texture = CONCRETE_NORMAL
    pillar_mat.uv1_scale = Vector3(1.5, 4, 1.5)
    pillar_mat.albedo_color = Color(0.8, 0.8, 0.82)
    pillar_mat.roughness = 0.88

    lamp_mat = StandardMaterial3D.new()
    lamp_mat.albedo_color = Color(0.9, 0.9, 0.85)
    lamp_mat.emission_enabled = true
    lamp_mat.emission = Color(1.0, 0.94, 0.78)
    lamp_mat.emission_energy_multiplier = 6.0
    lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    stand_mat = StandardMaterial3D.new()
    stand_mat.albedo_color = Color(0.18, 0.19, 0.21)
    stand_mat.metallic = 0.75
    stand_mat.roughness = 0.42


func _build_room() -> void:
    var floor := _static_box(self, "Floor", Vector3(24, 0.3, 42), Vector3(0, -0.15, -15), concrete_mat)
    floor.set_meta("surface", "concrete")
    var ceiling := _static_box(self, "Ceiling", Vector3(24, 0.2, 42), Vector3(0, 4.2, -15), ceiling_mat)
    ceiling.set_meta("surface", "concrete")
    var ceiling_mesh := ceiling.get_child(0) as MeshInstance3D
    if ceiling_mesh != null:
        ceiling_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var left := _static_box(self, "WallLeft", Vector3(0.3, 4.2, 42), Vector3(-12, 2.1, -15), wall_mat)
    left.set_meta("surface", "concrete")
    var right := _static_box(self, "WallRight", Vector3(0.3, 4.2, 42), Vector3(12, 2.1, -15), wall_mat)
    right.set_meta("surface", "concrete")
    var back := _static_box(self, "WallBack", Vector3(24, 4.2, 0.3), Vector3(0, 2.1, -36), wall_mat)
    back.set_meta("surface", "concrete")
    var front := _static_box(self, "WallFront", Vector3(24, 4.2, 0.3), Vector3(0, 2.1, 6), wall_mat)
    front.set_meta("surface", "concrete")


func _build_props() -> void:
    for data in [Vector2(-8, -10), Vector2(8, -10), Vector2(-8, -22), Vector2(8, -22)]:
        var pillar := _static_box(self, "Pillar", Vector3(0.5, 4.2, 0.5), Vector3(data.x, 2.1, data.y), pillar_mat)
        pillar.set_meta("surface", "concrete")

    _make_barrier(-5.8, -8.0, deg_to_rad(-8.0))
    _make_barrier(5.6, -14.5, deg_to_rad(10.0))
    _make_barrier(-5.4, -22.0, deg_to_rad(-6.0))

    _make_drum(6.6, -11.0)
    _make_drum(-6.8, -25.0)
    _make_drum(7.2, -27.0)


func _build_targets() -> void:
    for i in range(5):
        _make_paper_target(-4.0 + i * 2.0, -18.0)
    for i in range(3):
        _make_steel_target(-3.0 + i * 3.0, -27.0)


func _build_lights() -> void:
    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-58, -32, 0)
    sun.light_energy = 1.15
    sun.light_color = Color(1.0, 0.96, 0.9)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 55.0
    sun.shadow_bias = 0.08
    sun.shadow_normal_bias = 1.0
    sun.shadow_blur = 1.5
    sun.directional_shadow_blend_splits = true
    add_child(sun)

    for z in [-4.0, -12.0, -20.0, -28.0]:
        for x in [-5.0, 5.0]:
            _make_lamp(x, z)


func _make_lamp(x: float, z: float) -> void:
    var lamp := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(1.6, 0.07, 0.26)
    mesh.material = lamp_mat
    lamp.mesh = mesh
    lamp.position = Vector3(x, 4.05, z)
    lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(lamp)

    var light := OmniLight3D.new()
    light.position = Vector3(x, 3.55, z)
    light.light_color = Color(1.0, 0.96, 0.88)
    light.light_energy = 7.5
    light.omni_range = 9.0
    light.shadow_enabled = false
    add_child(light)


func _static_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = pos
    parent.add_child(body)

    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    box.material = mat
    mesh.mesh = box
    body.add_child(mesh)

    var shape := CollisionShape3D.new()
    var box_shape := BoxShape3D.new()
    box_shape.size = size
    shape.shape = box_shape
    body.add_child(shape)
    return body


func _make_barrier(x: float, z: float, rot_y: float) -> void:
    var root := Node3D.new()
    root.position = Vector3(x, 0, z)
    root.rotation.y = rot_y
    add_child(root)

    var board := _static_box(root, "BarrierBoard", Vector3(2.3, 0.72, 0.055), Vector3(0, 1.08, 0), wood_mat)
    board.set_meta("surface", "wood")
    board.set_meta("penetrable", true)
    board.set_meta("thickness", 0.055)
    board.set_meta("penetration_factor", 0.68)

    for leg_x in [-1.0, 1.0]:
        var leg := _static_box(root, "BarrierLeg", Vector3(0.08, 1.05, 0.08), Vector3(leg_x, 0.52, 0), wood_mat)
        leg.set_meta("surface", "wood")


func _make_drum(x: float, z: float) -> void:
    var body := StaticBody3D.new()
    body.name = "SteelDrum"
    body.position = Vector3(x, 0.46, z)
    add_child(body)

    var mesh_instance := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.height = 0.92
    mesh.top_radius = 0.29
    mesh.bottom_radius = 0.29
    mesh.radial_segments = 24
    mesh.material = metal_mat
    mesh_instance.mesh = mesh
    body.add_child(mesh_instance)

    var shape := CollisionShape3D.new()
    var cyl := CylinderShape3D.new()
    cyl.height = 0.92
    cyl.radius = 0.29
    shape.shape = cyl
    body.add_child(shape)
    body.set_meta("surface", "metal")


func _make_paper_target(x: float, z: float) -> void:
    var frame := StaticBody3D.new()
    frame.name = "PaperTargetFrame"
    frame.position = Vector3(x, 0, z)
    add_child(frame)

    for post_x in [-0.42, 0.42]:
        var post := _static_box(frame, "Post", Vector3(0.05, 1.78, 0.05), Vector3(post_x, 0.89, -0.12), stand_mat)
        post.set_meta("surface", "metal")
    var base := _static_box(frame, "Base", Vector3(1.1, 0.06, 0.5), Vector3(0, 0.03, -0.12), stand_mat)
    base.set_meta("surface", "metal")

    var target := Target.new()
    target.kind = "paper"
    target.name = "PaperTarget"
    add_child(target)
    target.global_position = Vector3(x, 1.35, z)

    _make_joint(frame, target, Vector3(x, 1.80, z))


func _make_steel_target(x: float, z: float) -> void:
    var frame := StaticBody3D.new()
    frame.name = "SteelTargetFrame"
    frame.position = Vector3(x, 0, z)
    add_child(frame)

    var post := _static_box(frame, "SteelPost", Vector3(0.07, 1.62, 0.07), Vector3(0, 0.81, -0.10), stand_mat)
    post.set_meta("surface", "metal")
    var base := _static_box(frame, "SteelBase", Vector3(0.7, 0.06, 0.5), Vector3(0, 0.03, -0.10), stand_mat)
    base.set_meta("surface", "metal")

    var target := Target.new()
    target.kind = "steel"
    target.name = "SteelTarget"
    add_child(target)
    target.global_position = Vector3(x, 1.35, z)

    _make_joint(frame, target, Vector3(x, 1.66, z))


func _make_joint(frame: StaticBody3D, target: RigidBody3D, pivot: Vector3) -> void:
    var joint := PinJoint3D.new()
    frame.add_child(joint)
    joint.node_a = frame.get_path()
    joint.node_b = target.get_path()
    joint.global_position = pivot
