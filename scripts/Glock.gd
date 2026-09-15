extends Node3D

signal shot_fired
signal ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool)

const MAG_SIZE := 17
const GRAVITY := 9.8

var camera: Camera3D
var pose_root: Node3D
var recoil_node: Node3D
var slide: Node3D
var barrel_group: Node3D
var mag_group: Node3D
var trigger_mesh: MeshInstance3D
var muzzle: Node3D
var ejection_port: Node3D
var muzzle_flash: MeshInstance3D
var muzzle_flash_2: MeshInstance3D
var muzzle_light: OmniLight3D

var slide_mat: StandardMaterial3D
var frame_mat: StandardMaterial3D
var steel_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var brass_mat: StandardMaterial3D
var hand_mat: StandardMaterial3D
var sight_mat: StandardMaterial3D
var flash_mat: StandardMaterial3D

var mag := 17
var chamber := 1
var reserve := 68
var trigger_held := false
var trigger_ready := true
var trigger_latched := false
var trigger_reset_timer := 0.0

var slide_pos := 0.0
var slide_vel := 0.0
var slide_locked := false
var slide_extracted := false

var recoil_pos := Vector3.ZERO
var recoil_vel := Vector3.ZERO
var recoil_rot := Vector3.ZERO
var recoil_rot_vel := Vector3.ZERO

var aim := false
var sprinting := false
var aim_blend := 0.0
var sprint_blend := 0.0

var muzzle_timer := 0.0
var shot_pulse := 0.0

var reloading := false
var reload_elapsed := 0.0
var reload_total := 0.0
var reload_empty := false
var reload_slide_released := false
var mag_inserted_sound := false
var mag_base_y := -0.135
var mag_base_z := 0.022

var player_speed := 0.0
var look_delta := Vector2.ZERO
var bob_phase := 0.0
var idle_phase := 0.0
var sway := Vector2.ZERO
var player_velocity := Vector3.ZERO

var muzzle_world_pos := Vector3.ZERO

var model_root: Node3D
var skeleton: Skeleton3D
var glock_mesh: MeshInstance3D
var bone_slide := -1
var bone_trigger := -1
var bone_magazine := -1
var bone_barrel := -1
var rest_slide := Transform3D.IDENTITY
var rest_trigger := Transform3D.IDENTITY
var rest_magazine := Transform3D.IDENTITY
var slide_axis := Vector3(0, 1, 0)
var magazine_axis := Vector3(0, 0, -1)
var model_units_per_meter := 0.241
var mag_visual_drop := 0.0
var reload_pose_blend := 0.0
var trigger_visual := 0.0


func _ready() -> void:
    pose_root = Node3D.new()
    pose_root.name = "PoseRoot"
    add_child(pose_root)

    recoil_node = Node3D.new()
    recoil_node.name = "RecoilNode"
    pose_root.add_child(recoil_node)

    _build_materials()
    _build_model()
    _setup_bones()
    _emit_ammo()


func setup(cam: Camera3D) -> void:
    camera = cam


func set_aim(value: bool) -> void:
    aim = value


func set_sprint(value: bool) -> void:
    sprinting = value


func set_motion(speed: float, local_move: Vector2, look: Vector2) -> void:
    player_speed = speed
    look_delta = look
    _last_local_move = local_move


var _last_local_move := Vector2.ZERO


func press_trigger() -> void:
    trigger_held = true


func release_trigger() -> void:
    trigger_held = false


func force_fire_once() -> void:
    if _can_fire():
        _fire()


func start_reload() -> bool:
    if reloading or reserve <= 0:
        return false
    if chamber > 0 and mag >= MAG_SIZE:
        return false
    reloading = true
    reload_elapsed = 0.0
    reload_empty = chamber <= 0 and slide_locked
    reload_total = 2.36 if reload_empty else 1.72
    reload_slide_released = false
    mag_inserted_sound = false
    aim = false
    trigger_held = false
    GameAudio.play_2d("magout", -3.0, randf_range(0.95, 1.05))
    _emit_ammo()
    return true


func _can_fire() -> bool:
    return not reloading and chamber > 0 and absf(slide_pos) < 0.0025


func _process(delta: float) -> void:
    _update_trigger(delta)
    _update_slide(delta)
    _update_recoil(delta)
    _update_reload(delta)
    _update_pose(delta)
    _apply_bone_poses()

    muzzle_timer = maxf(0.0, muzzle_timer - delta)
    shot_pulse = maxf(0.0, shot_pulse - delta * 8.0)

    var flash_visible := muzzle_timer > 0.0
    if muzzle_flash != null:
        muzzle_flash.visible = flash_visible
    if muzzle_flash_2 != null:
        muzzle_flash_2.visible = flash_visible
    if muzzle_light != null:
        muzzle_light.light_energy = 8.0 if flash_visible else 0.0


func _update_trigger(delta: float) -> void:
    trigger_visual += ((1.0 if trigger_held else 0.0) - trigger_visual) * (1.0 - exp(-18.0 * delta))

    if trigger_held and trigger_ready and _can_fire():
        _fire()
        return

    if not trigger_held:
        if trigger_latched:
            trigger_reset_timer -= delta
            if trigger_reset_timer <= 0.0:
                trigger_ready = true
                trigger_latched = false
        else:
            trigger_ready = true


func _fire() -> void:
    chamber -= 1
    trigger_ready = false
    trigger_latched = true
    trigger_reset_timer = 0.075
    slide_extracted = false
    slide_vel += 4.35
    shot_pulse = 1.0

    recoil_vel += Vector3((randf() - 0.5) * 0.18, 0.09, 0.62)
    recoil_rot_vel += Vector3(5.4 + randf() * 1.3, (randf() - 0.5) * 1.3, (randf() - 0.5) * 1.5)

    muzzle_timer = 0.04
    muzzle_flash.rotation.z = randf_range(0.0, TAU)
    muzzle_flash.scale = Vector3.ONE * randf_range(0.85, 1.35)
    muzzle_flash_2.rotation.z = randf_range(0.0, TAU)
    muzzle_flash_2.scale = Vector3.ONE * randf_range(0.7, 1.2)

    GameAudio.play_shot(-1.8)

    var origin := muzzle.global_position
    var cam_fwd := -camera.global_transform.basis.z.normalized()
    var aim_point := camera.global_position + cam_fwd * 46.0
    var dir := (aim_point - origin).normalized()
    var right := camera.global_transform.basis.x.normalized()
    var up := camera.global_transform.basis.y.normalized()
    var move_amount := clampf(player_speed / 4.35, 0.0, 1.0)
    var spread := 0.00055 if aim_blend > 0.55 else 0.0036 + move_amount * 0.0052
    dir = (dir + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()

    Ballistics.fire(origin, dir, 372.0, 0.42)
    ImpactFX.spawn_muzzle_smoke(origin, cam_fwd)

    emit_signal("shot_fired")
    _emit_ammo()


func _update_slide(delta: float) -> void:
    var steps := 3
    var h := delta / float(steps)
    for _i in range(steps):
        if slide_locked:
            slide_pos = 0.039
            slide_vel = 0.0
            break
        slide_vel += (-8800.0 * slide_pos - 92.0 * slide_vel) * h
        slide_pos += slide_vel * h
        if slide_pos < 0.0:
            slide_pos = 0.0
            slide_vel = maxf(0.0, slide_vel)
        if slide_pos > 0.045:
            slide_pos = 0.045
            slide_vel = minf(0.0, slide_vel)

    if slide != null:
        slide.position.z = slide_pos
    if barrel_group != null:
        barrel_group.position.z = slide_pos * 0.34

    if not slide_extracted and slide_pos > 0.021:
        slide_extracted = true
        _spawn_shell()

    if slide_pos < 0.001 and slide_vel <= 0.0 and chamber <= 0 and mag > 0:
        mag -= 1
        chamber = 1
        _emit_ammo()

    if slide_pos > 0.034 and mag <= 0 and chamber <= 0 and not reloading:
        slide_locked = true
        slide_pos = 0.039
        slide_vel = 0.0
        GameAudio.play_2d("slide", -4.0)


func _update_recoil(delta: float) -> void:
    var steps := 2
    var h := delta / float(steps)
    for _i in range(steps):
        recoil_vel += (-330.0 * recoil_pos - 20.0 * recoil_vel) * h
        recoil_pos += recoil_vel * h
        recoil_rot_vel += (-300.0 * recoil_rot - 18.0 * recoil_rot_vel) * h
        recoil_rot += recoil_rot_vel * h
    recoil_pos = Vector3(clampf(recoil_pos.x, -0.05, 0.05), clampf(recoil_pos.y, -0.05, 0.05), clampf(recoil_pos.z, -0.05, 0.09))
    recoil_rot = Vector3(clampf(recoil_rot.x, -0.35, 0.35), clampf(recoil_rot.y, -0.2, 0.2), clampf(recoil_rot.z, -0.25, 0.25))
    recoil_node.position = recoil_pos
    recoil_node.rotation = recoil_rot


func _update_reload(delta: float) -> void:
    if not reloading:
        return
    reload_elapsed += delta
    var seat_start := 1.16 if reload_empty else 0.98
    var out_t := clampf((reload_elapsed - 0.1) / 0.3, 0.0, 1.0)
    var in_t := clampf((reload_elapsed - (seat_start - 0.22)) / 0.3, 0.0, 1.0)

    if mag_group != null:
        if reload_elapsed < seat_start - 0.22:
            mag_group.position = Vector3(0.0, mag_base_y - 0.17 * _smooth(out_t), mag_base_z - 0.03 * _smooth(out_t))
        elif reload_elapsed < seat_start:
            mag_group.position = Vector3(0.0, mag_base_y - 0.14, mag_base_z - 0.01)
        else:
            mag_group.position = Vector3(0.0, mag_base_y - 0.14 * (1.0 - _smooth(in_t)), mag_base_z)
        mag_group.rotation.x = deg_to_rad(-15.0 + 12.0 * _smooth(in_t))

    if reload_elapsed > seat_start and not mag_inserted_sound:
        mag_inserted_sound = true
        GameAudio.play_2d("magin", -3.0, randf_range(0.95, 1.05))

    if reload_empty and not reload_slide_released and reload_elapsed > 1.72:
        reload_slide_released = true
        slide_locked = false
        slide_pos = 0.039
        slide_vel = -4.2
        GameAudio.play_2d("slide", -3.0)

    var drop_t := 0.0
    if reload_elapsed < seat_start - 0.22:
        drop_t = _smooth(out_t)
    elif reload_elapsed < seat_start:
        drop_t = 1.0
    else:
        drop_t = 1.0 - _smooth(in_t)
    mag_visual_drop = drop_t * 0.20
    reload_pose_blend = sin(clampf(reload_elapsed / maxf(reload_total, 0.001), 0.0, 1.0) * PI)

    if reload_elapsed >= reload_total:
        _finish_reload()


func _finish_reload() -> void:
    var available := mini(MAG_SIZE, reserve)
    reloading = false
    mag_inserted_sound = false
    if available <= 0:
        return
    reserve -= available
    if reload_empty:
        mag = available
        chamber = 0
        slide_locked = false
    else:
        mag = available
        chamber = 1
    if mag_group != null:
        mag_group.position = Vector3(0.0, mag_base_y, mag_base_z)
        mag_group.rotation.x = deg_to_rad(-15.0)
    mag_visual_drop = 0.0
    reload_pose_blend = 0.0
    _emit_ammo()


func _update_pose(delta: float) -> void:
    idle_phase += delta
    var target_sprint := 1.0 if sprinting else 0.0
    sprint_blend += (target_sprint - sprint_blend) * (1.0 - exp(-5.5 * delta))
    var target_aim := (1.0 if aim else 0.0) * (1.0 - sprint_blend)
    aim_blend += (target_aim - aim_blend) * (1.0 - exp(-9.0 * delta))

    sway.x += (-look_delta.x * 0.055 - sway.x) * (1.0 - exp(-10.0 * delta))
    sway.y += (-look_delta.y * 0.055 - sway.y) * (1.0 - exp(-10.0 * delta))

    if player_speed > 0.25:
        bob_phase += delta * (1.8 + player_speed * 1.45)

    var hip_pos := Vector3.ZERO
    var ads_pos := Vector3(-0.17, 0.138, 0.105)
    var sprint_pos := Vector3(0.05, -0.135, -0.02)
    var hip_rot := Vector3.ZERO
    var ads_rot := Vector3.ZERO
    var sprint_rot := Vector3(deg_to_rad(-14.0), deg_to_rad(-5.0), deg_to_rad(5.0))

    var carry_pos := hip_pos.lerp(sprint_pos, sprint_blend)
    var carry_rot := hip_rot.lerp(sprint_rot, sprint_blend)
    var pos := carry_pos.lerp(ads_pos, aim_blend)
    var rot := carry_rot.lerp(ads_rot, aim_blend)

    var move_norm := clampf(player_speed / 4.35, 0.0, 1.0)
    pos.x += cos(bob_phase * 0.5) * 0.0045 * move_norm + sway.x * (1.0 - aim_blend * 0.65)
    pos.y += sin(bob_phase) * 0.0065 * move_norm + sin(idle_phase * 1.05) * 0.0016 * (1.0 - aim_blend * 0.55) + sway.y * (1.0 - aim_blend * 0.65)
    pos.x -= _last_local_move.x * 0.02 * (1.0 - aim_blend * 0.5)
    pos.y -= absf(_last_local_move.y) * 0.008 * (1.0 - aim_blend * 0.5)

    rot.x += sway.y * 0.5 + sin(idle_phase * 1.05) * 0.0025 * (1.0 - aim_blend * 0.6) - _last_local_move.y * 0.008
    rot.y += sway.x * 0.5 + sin(idle_phase * 0.73 + 1.0) * 0.0020 * (1.0 - aim_blend * 0.6)
    rot.z += -_last_local_move.x * 0.012 - sin(bob_phase) * 0.012 * sprint_blend

    pos.y -= reload_pose_blend * 0.07
    pos.z += reload_pose_blend * 0.03
    rot.x += reload_pose_blend * 0.32
    pose_root.position = pos
    pose_root.rotation = rot


func _spawn_shell() -> void:
    if not is_instance_valid(get_tree().current_scene):
        return
    var shell = preload("res://scripts/Shell.gd").new()
    shell.mass = 0.008
    shell.collision_layer = 2
    shell.collision_mask = 1
    shell.continuous_cd = true

    var cylinder := CylinderMesh.new()
    cylinder.height = 0.0195
    cylinder.top_radius = 0.00425
    cylinder.bottom_radius = 0.00425
    cylinder.radial_segments = 10
    cylinder.material = brass_mat
    var shell_mesh := MeshInstance3D.new()
    shell_mesh.mesh = cylinder
    shell.add_child(shell_mesh)

    var shape := CylinderShape3D.new()
    shape.height = 0.0195
    shape.radius = 0.00425
    var collider := CollisionShape3D.new()
    collider.shape = shape
    shell.add_child(collider)

    var physics_mat := PhysicsMaterial.new()
    physics_mat.bounce = 0.52
    physics_mat.friction = 0.45
    shell.physics_material_override = physics_mat

    get_tree().current_scene.add_child(shell)
    shell.global_transform = ejection_port.global_transform
    var basis := ejection_port.global_transform.basis
    var local_vel := Vector3(1.5 + randf() * 1.1, -1.0 - randf() * 0.6, 1.7 + randf() * 0.9)
    shell.linear_velocity = basis * local_vel + player_velocity * 0.8
    shell.angular_velocity = Vector3(randf_range(-16.0, 16.0), randf_range(-16.0, 16.0), randf_range(-16.0, 16.0))


func _emit_ammo() -> void:
    ammo_changed.emit(mag, chamber, reserve, reloading)


func _smooth(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


func _build_materials() -> void:
    slide_mat = StandardMaterial3D.new()
    slide_mat.albedo_color = Color(0.045, 0.048, 0.055)
    slide_mat.metallic = 0.9
    slide_mat.roughness = 0.28

    frame_mat = StandardMaterial3D.new()
    frame_mat.albedo_color = Color(0.028, 0.029, 0.032)
    frame_mat.metallic = 0.05
    frame_mat.roughness = 0.62

    steel_mat = StandardMaterial3D.new()
    steel_mat.albedo_color = Color(0.58, 0.59, 0.63)
    steel_mat.metallic = 0.96
    steel_mat.roughness = 0.24

    dark_mat = StandardMaterial3D.new()
    dark_mat.albedo_color = Color(0.006, 0.006, 0.009)
    dark_mat.metallic = 0.35
    dark_mat.roughness = 0.72

    brass_mat = StandardMaterial3D.new()
    brass_mat.albedo_color = Color(0.72, 0.51, 0.14)
    brass_mat.metallic = 1.0
    brass_mat.roughness = 0.32

    hand_mat = StandardMaterial3D.new()
    hand_mat.albedo_color = Color(0.16, 0.115, 0.088)
    hand_mat.roughness = 0.78

    sight_mat = StandardMaterial3D.new()
    sight_mat.albedo_color = Color(0.62, 1.0, 0.58)
    sight_mat.emission_enabled = true
    sight_mat.emission = Color(0.35, 1.0, 0.38)
    sight_mat.emission_energy_multiplier = 5.0
    sight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    flash_mat = StandardMaterial3D.new()
    flash_mat.albedo_texture = preload("res://assets/textures/muzzle_flash.png")
    flash_mat.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
    flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    flash_mat.emission_enabled = true
    flash_mat.emission = Color(1.0, 0.55, 0.15)
    flash_mat.emission_energy_multiplier = 5.0
    flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _build_model() -> void:
    var packed := load("res://assets/models/glock_rigged.glb") as PackedScene
    # El GLB viene de FBX2glTF con escala interna de armature (~48.3).
    # Lo normalizamos para que el arma mida ~18.6 cm reales.
    const LOCAL_LENGTH := 0.045424
    const DESIRED_LENGTH := 0.186
    const ARMATURE_SCALE := 48.2968
    var visual_scale := DESIRED_LENGTH / LOCAL_LENGTH
    var root_scale := visual_scale / ARMATURE_SCALE
    model_units_per_meter = 1.0 / visual_scale
    if packed != null:
        model_root = packed.instantiate()
        model_root.name = "GlockModel"
        # Modelo local: +X derecha, +Y cañón, +Z arriba.
        # Godot arma local: +X derecha, -Z cañón (adelante), +Y arriba.
        var target_basis := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
        model_root.transform.basis = target_basis.scaled(Vector3(root_scale, root_scale, root_scale))
        model_root.position = Vector3(0.0, 0.0, 0.0)
        recoil_node.add_child(model_root)

        skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
        glock_mesh = model_root.find_child("Glock19", true, false) as MeshInstance3D
        var bullet_mesh := model_root.find_child("Glock19_001", true, false) as MeshInstance3D
        if bullet_mesh != null:
            bullet_mesh.visible = false
        _apply_model_materials()
    else:
        push_error("No se pudo cargar el modelo Glock riggeado")

    slide = Node3D.new()
    slide.name = "SlideMarker"
    recoil_node.add_child(slide)
    barrel_group = Node3D.new()
    barrel_group.name = "BarrelMarker"
    recoil_node.add_child(barrel_group)
    mag_group = Node3D.new()
    mag_group.name = "MagMarker"
    recoil_node.add_child(mag_group)
    trigger_mesh = MeshInstance3D.new()
    trigger_mesh.name = "TriggerDummy"
    recoil_node.add_child(trigger_mesh)

    var marker_parent: Node3D = skeleton if skeleton != null else (model_root if model_root != null else recoil_node)
    muzzle = Node3D.new()
    muzzle.name = "Muzzle"
    marker_parent.add_child(muzzle)
    muzzle.position = Vector3(0.0, 0.0235, 0.0145)
    _build_flash()

    ejection_port = Node3D.new()
    ejection_port.name = "EjectionPort"
    marker_parent.add_child(ejection_port)
    ejection_port.position = Vector3(0.0036, 0.010, 0.016)


func _build_flash() -> void:
    muzzle_flash = MeshInstance3D.new()
    var flash_quad := QuadMesh.new()
    flash_quad.size = Vector2(0.075, 0.075)
    flash_quad.material = flash_mat
    muzzle_flash.mesh = flash_quad
    muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    muzzle_flash.visible = false
    muzzle.add_child(muzzle_flash)

    muzzle_flash_2 = MeshInstance3D.new()
    var core_quad := QuadMesh.new()
    core_quad.size = Vector2(0.036, 0.036)
    core_quad.material = flash_mat
    muzzle_flash_2.mesh = core_quad
    muzzle_flash_2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    muzzle_flash_2.visible = false
    muzzle.add_child(muzzle_flash_2)

    muzzle_light = OmniLight3D.new()
    muzzle_light.light_color = Color(1.0, 0.78, 0.4)
    muzzle_light.light_energy = 0.0
    muzzle_light.omni_range = 5.5
    muzzle_light.shadow_enabled = false
    muzzle.add_child(muzzle_light)


func _apply_model_materials() -> void:
    if glock_mesh == null or glock_mesh.mesh == null:
        return
    var mats: Array[Material] = [
        frame_mat, dark_mat, slide_mat,
        steel_mat, steel_mat, dark_mat,
        brass_mat, brass_mat, brass_mat,
    ]
    var count := mini(glock_mesh.mesh.get_surface_count(), mats.size())
    for i in range(count):
        glock_mesh.set_surface_override_material(i, mats[i])
    glock_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _setup_bones() -> void:
    if skeleton == null:
        return
    bone_slide = skeleton.find_bone("Slide")
    bone_trigger = skeleton.find_bone("Trigger")
    bone_magazine = skeleton.find_bone("Magazine")
    bone_barrel = skeleton.find_bone("Barrel")

    if bone_slide >= 0:
        rest_slide = skeleton.get_bone_rest(bone_slide)
    if bone_trigger >= 0:
        rest_trigger = skeleton.get_bone_rest(bone_trigger)
    if bone_magazine >= 0:
        rest_magazine = skeleton.get_bone_rest(bone_magazine)

    var root_idx := skeleton.find_bone("Root")
    if root_idx >= 0:
        var root_rest := skeleton.get_bone_global_rest(root_idx)
        var inverse_root := root_rest.basis.inverse()
        # Modelo local: +Y = frente del cañón, +Z = arriba.
        slide_axis = (inverse_root * Vector3(0, -1, 0)).normalized()
        magazine_axis = (inverse_root * Vector3(0, 0, -1)).normalized()


func _apply_bone_poses() -> void:
    if skeleton == null:
        return
    if bone_slide >= 0:
        var slide_units := slide_pos * model_units_per_meter
        skeleton.set_bone_pose_position(bone_slide, rest_slide.origin + slide_axis * slide_units)
    if bone_magazine >= 0:
        var mag_units := mag_visual_drop * model_units_per_meter
        skeleton.set_bone_pose_position(bone_magazine, rest_magazine.origin + magazine_axis * mag_units)
    if bone_trigger >= 0:
        var angle := -0.30 * trigger_visual
        var trigger_basis := rest_trigger.basis.rotated(Vector3(1, 0, 0), angle)
        skeleton.set_bone_pose_rotation(bone_trigger, trigger_basis)


func _box(parent: Node3D, mesh_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
    var box := BoxMesh.new()
    box.size = size
    box.material = mat
    var mesh := MeshInstance3D.new()
    mesh.name = mesh_name
    mesh.mesh = box
    mesh.position = pos
    parent.add_child(mesh)
    return mesh


func _cylinder(parent: Node3D, mesh_name: String, height: float, diameter: float, pos: Vector3, mat: Material, rotation_deg := Vector3.ZERO) -> MeshInstance3D:
    var cyl := CylinderMesh.new()
    cyl.height = height
    cyl.top_radius = diameter * 0.5
    cyl.bottom_radius = diameter * 0.5
    cyl.radial_segments = 18
    cyl.material = mat
    var mesh := MeshInstance3D.new()
    mesh.name = mesh_name
    mesh.mesh = cyl
    mesh.position = pos
    mesh.rotation_degrees = rotation_deg
    parent.add_child(mesh)
    return mesh


func _capsule(parent: Node3D, mesh_name: String, height: float, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
    var cap := CapsuleMesh.new()
    cap.height = height
    cap.radius = radius
    cap.material = mat
    var mesh := MeshInstance3D.new()
    mesh.name = mesh_name
    mesh.mesh = cap
    mesh.position = pos
    parent.add_child(mesh)
    return mesh
