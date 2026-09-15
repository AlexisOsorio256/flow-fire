extends Node3D

const HOLE_TEXTURE: Texture2D = preload("res://assets/textures/bullet_hole.png")
const SOFT_TEXTURE: Texture2D = preload("res://assets/textures/particle_soft.png")
const SPARK_TEXTURE: Texture2D = preload("res://assets/textures/particle_spark.png")

var decals: Array[Decal] = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS


func spawn_impact(point: Vector3, normal: Vector3, collider: Object, surface: String, is_exit: bool = false) -> void:
    _spawn_decal(point, normal, collider, surface, is_exit)
    _spawn_particles(point, normal, surface, is_exit)
    _spawn_light(point, surface)

    var sound_name := "impact_concrete"
    var volume := 0.0
    match surface:
        "metal":
            sound_name = "impact_metal"
        "wood":
            sound_name = "impact_wood"
        "paper":
            sound_name = "impact_wood"
            volume = -10.0
        _:
            sound_name = "impact_concrete"
    if not (is_exit and surface == "paper"):
        GameAudio.play_3d(sound_name, point, volume, randf_range(0.92, 1.08))


func spawn_muzzle_smoke(point: Vector3, direction: Vector3) -> void:
    var pm := ParticleProcessMaterial.new()
    pm.direction = direction.normalized()
    pm.spread = 24.0
    pm.initial_velocity_min = 0.25
    pm.initial_velocity_max = 0.9
    pm.gravity = Vector3(0, 0.35, 0)
    pm.scale_min = 0.45
    pm.scale_max = 1.8
    pm.color = Color(0.55, 0.55, 0.52, 0.24)
    pm.damping_min = 1.2
    pm.damping_max = 2.0

    var particles := GPUParticles3D.new()
    particles.amount = 7
    particles.lifetime = 0.9
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.process_material = pm
    particles.draw_pass_1 = _particle_quad(SOFT_TEXTURE, Color(0.6, 0.6, 0.58, 0.28), false, 0.055)
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(particles)
    particles.global_position = point
    get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


func _spawn_decal(point: Vector3, normal: Vector3, collider: Object, surface: String, is_exit: bool) -> void:
    var size := 0.085
    match surface:
        "metal":
            size = 0.055
        "paper":
            size = 0.032
        "wood":
            size = 0.07
    if is_exit:
        size *= 0.78

    var decal := Decal.new()
    decal.texture_albedo = HOLE_TEXTURE
    decal.size = Vector3(size, size, 0.17)
    decal.albedo_mix = 1.0
    decal.modulate = Color(1, 1, 1, 0.98)
    decal.upper_fade = 0.14
    decal.lower_fade = 0.14
    decal.distance_fade_enabled = true
    decal.distance_fade_begin = 26.0
    decal.distance_fade_length = 8.0
    decal.rotation_degrees = Vector3(0, randf_range(0.0, 360.0), 0)

    var y_axis := -normal.normalized()
    var up_ref := Vector3.UP
    if abs(y_axis.dot(up_ref)) > 0.94:
        up_ref = Vector3.RIGHT
    var x_axis := up_ref.cross(y_axis).normalized()
    var z_axis := x_axis.cross(y_axis).normalized()
    decal.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), point + normal.normalized() * 0.009)
    add_child(decal)

    if collider is Node3D and collider.get_meta("dynamic_decal", false):
        decal.reparent(collider, true)

    decals.append(decal)
    if decals.size() > 120:
        var old: Decal = decals.pop_front()
        if is_instance_valid(old):
            old.queue_free()


func _spawn_particles(point: Vector3, normal: Vector3, surface: String, is_exit: bool) -> void:
    var metal := surface == "metal"
    var pm := ParticleProcessMaterial.new()
    pm.direction = normal.normalized()
    pm.spread = 58.0
    if metal:
        pm.gravity = Vector3(0, -11.0, 0)
        pm.initial_velocity_min = 2.6
        pm.initial_velocity_max = 7.0
        pm.scale_min = 0.35
        pm.scale_max = 1.25
        pm.color = Color(1.0, 0.62, 0.18, 1.0)
        pm.damping_min = 0.4
        pm.damping_max = 0.9
    else:
        pm.gravity = Vector3(0, -2.2, 0)
        pm.initial_velocity_min = 0.4
        pm.initial_velocity_max = 2.0
        pm.scale_min = 0.55
        pm.scale_max = 2.4
        pm.damping_min = 1.0
        pm.damping_max = 2.2
        match surface:
            "wood":
                pm.color = Color(0.42, 0.28, 0.14, 0.75)
            "paper":
                pm.color = Color(0.82, 0.79, 0.72, 0.55)
            _:
                pm.color = Color(0.53, 0.52, 0.50, 0.65)

    var particles := GPUParticles3D.new()
    particles.amount = 5 if (surface == "paper" or is_exit) else (16 if metal else 12)
    particles.lifetime = 0.32 if metal else 0.75
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.process_material = pm
    if metal:
        particles.draw_pass_1 = _particle_quad(SPARK_TEXTURE, Color(1.0, 0.7, 0.25, 1.0), true, 0.018)
    else:
        particles.draw_pass_1 = _particle_quad(SOFT_TEXTURE, pm.color, false, 0.045)
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(particles)
    particles.global_position = point + normal.normalized() * 0.01
    get_tree().create_timer(particles.lifetime + 0.5).timeout.connect(particles.queue_free)


func _spawn_light(point: Vector3, surface: String) -> void:
    var light := OmniLight3D.new()
    light.omni_range = 2.7
    light.light_energy = 4.5
    light.light_color = Color(1.0, 0.72, 0.34) if surface == "metal" else Color(0.8, 0.76, 0.68)
    light.shadow_enabled = false
    add_child(light)
    light.global_position = point + Vector3.UP * 0.05
    var tween := create_tween()
    tween.tween_property(light, "light_energy", 0.0, 0.09)
    tween.finished.connect(light.queue_free)


func _particle_quad(texture: Texture2D, color: Color, additive: bool, size: float) -> QuadMesh:
    var quad := QuadMesh.new()
    quad.size = Vector2(size, size)
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = texture
    mat.albedo_color = color
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    mat.billboard_keep_scale = true
    mat.vertex_color_use_as_albedo = true
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    quad.material = mat
    return quad
