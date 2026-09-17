extends RigidBody3D
class_name Target

var kind := "paper"
var max_health := 100.0
var health := 100.0
var dead := false
var last_hit_zone := "TORSO"
var plate_height := 0.9
var plate_width := 0.66

var plate_mesh: MeshInstance3D
var base_material: StandardMaterial3D


func _ready() -> void:
    mass = 2.0 if kind == "paper" else 6.0
    collision_layer = 1
    collision_mask = 1
    continuous_cd = true
    set_meta("dynamic_decal", true)
    linear_damp = 0.4
    angular_damp = 0.5
    _build_visuals()

    if kind == "paper":
        max_health = 100.0
        health = 100.0
        plate_height = 0.9
        plate_width = 0.66
        set_meta("surface", "paper")
        set_meta("penetrable", true)
        set_meta("penetration_resistance", 1.70)
    else:
        max_health = 150.0
        health = 150.0
        plate_height = 0.62
        plate_width = 0.62
        set_meta("surface", "metal")
        set_meta("penetrable", false)


func _build_visuals() -> void:
    if kind == "paper":
        base_material = StandardMaterial3D.new()
        base_material.albedo_texture = preload("res://assets/textures/target_paper.png")
        base_material.roughness = 0.95
        base_material.cull_mode = BaseMaterial3D.CULL_DISABLED
        var box := BoxMesh.new()
        box.size = Vector3(plate_width, plate_height, 0.022)
        box.material = base_material
        plate_mesh = MeshInstance3D.new()
        plate_mesh.mesh = box
        add_child(plate_mesh)

        var shape := BoxShape3D.new()
        shape.size = Vector3(plate_width, plate_height, 0.022)
        var collider := CollisionShape3D.new()
        collider.shape = shape
        add_child(collider)
    else:
        base_material = StandardMaterial3D.new()
        base_material.albedo_texture = preload("res://assets/textures/metal_albedo.png")
        base_material.metallic = 0.9
        base_material.roughness = 0.28
        var cylinder := CylinderMesh.new()
        cylinder.height = 0.022
        cylinder.top_radius = 0.31
        cylinder.bottom_radius = 0.31
        cylinder.radial_segments = 32
        cylinder.material = base_material
        plate_mesh = MeshInstance3D.new()
        plate_mesh.mesh = cylinder
        plate_mesh.rotation_degrees = Vector3(90, 0, 0)
        add_child(plate_mesh)

        var shape := CylinderShape3D.new()
        shape.height = 0.022
        shape.radius = 0.31
        var collider := CollisionShape3D.new()
        collider.shape = shape
        collider.rotation_degrees = Vector3(90, 0, 0)
        add_child(collider)


func take_bullet_hit(point: Vector3, normal: Vector3, speed: float, energy: float, direction := Vector3.ZERO) -> void:
    if dead:
        return
    var local_point := to_local(point)
    var zone := "TORSO"
    var multiplier := 1.0
    var armor := 1.0
    if kind == "steel":
        zone = "PLACA"
        armor = 0.55
    elif local_point.y > plate_height * 0.28:
        zone = "CABEZA"
        multiplier = 3.1
    elif local_point.y < -plate_height * 0.22:
        zone = "PIERNA"
        multiplier = 0.65

    var damage := 44.0 * (energy / 520.0) * multiplier * armor
    health = max(0.0, health - damage)
    last_hit_zone = zone
    set_meta("last_hit_zone", zone)

    var push := direction.normalized() if direction.length_squared() > 0.1 else -normal.normalized()
    var impulse_strength := 0.9 + damage * 0.02
    apply_impulse(push * impulse_strength, point - global_position)
    apply_torque_impulse(Vector3(randf_range(-0.08, 0.08), randf_range(-0.12, 0.12), randf_range(-0.08, 0.08)))

    _flash()

    if health <= 0.0:
        dead = true
        set_meta("dead", true)
        angular_velocity += Vector3(randf_range(-2.4, -1.0), randf_range(-1.0, 1.0), randf_range(-0.8, 0.8))
        apply_impulse(push * 2.5, point - global_position)


func _flash() -> void:
    if base_material == null:
        return
    base_material.emission_enabled = true
    base_material.emission = Color(1.0, 0.12, 0.05)
    base_material.emission_energy_multiplier = 3.6
    var tween := create_tween()
    tween.tween_property(base_material, "emission_energy_multiplier", 0.0, 0.09)
