extends Node3D

signal shot_fired
signal ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool)

const MAG_SIZE := 17
const GRAVITY := 9.8
const GUN_LENGTH := 0.186  # Glock 19 real: 186 mm de punta a punta.
const ADS_SIGHT_DISTANCE := 0.55  # Ojo -> mira trasera con el brazo extendido.
const ADS_SIGHT_DROP := 0.008  # La mira queda algo bajo el centro para no taparlo.
const HIP_POS := Vector3(0.0, -0.05, 0.0)  # Pose de lista: el arma va baja.

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
var reload_mag_seated := false
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
var gun_frame: Node3D
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
var sight_marker: Node3D
var ads_offset := Vector3(-0.17, 0.138, 0.105)
# Base real del arma medida en runtime sobre la malla del GLB (ver _measure_mesh).
var gun_frame_bind := Basis.IDENTITY
var bind_in_skeleton := Transform3D.IDENTITY
var mesh_to_weapon := Transform3D.IDENTITY


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
    _compute_ads_offset()


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
    reload_mag_seated = false
    mag_inserted_sound = false
    aim = false
    trigger_held = false
    GameAudio.play_2d("magout", 0.0, randf_range(0.95, 1.05))
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
        muzzle_light.light_energy = randf_range(5.5, 10.5) if flash_visible else 0.0


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

    GameAudio.play_shot()

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
    if slide_locked:
        slide_pos = 0.039
        slide_vel = 0.0
    else:
        var integrated := Springs.scalar(slide_pos, slide_vel, 8800.0, 92.0, delta)
        slide_pos = clampf(integrated.x, 0.0, 0.045)
        slide_vel = integrated.y
        if slide_pos <= 0.0 or slide_pos >= 0.045:
            # Topes reales: la corredera no rebota contra ellos.
            slide_vel = maxf(0.0, slide_vel) if slide_pos <= 0.0 else minf(0.0, slide_vel)

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
        GameAudio.play_2d("slide")


func _update_recoil(delta: float) -> void:
    var pos := Springs.vector(recoil_pos, recoil_vel, 330.0, 20.0, delta)
    recoil_pos = pos[0]
    recoil_vel = pos[1]
    var rot := Springs.vector(recoil_rot, recoil_rot_vel, 300.0, 18.0, delta)
    recoil_rot = rot[0]
    recoil_rot_vel = rot[1]
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

    if reload_elapsed >= seat_start and not reload_mag_seated:
        _seat_reload_mag()

    if reload_elapsed > seat_start and not mag_inserted_sound:
        mag_inserted_sound = true
        GameAudio.play_2d("magin", 0.0, randf_range(0.95, 1.05))

    if reload_empty and not reload_slide_released and reload_elapsed > 1.72:
        reload_slide_released = true
        slide_locked = false
        slide_pos = 0.039
        slide_vel = -4.2
        GameAudio.play_2d("slide", 1.0)

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


func _seat_reload_mag() -> void:
    if reload_mag_seated:
        return
    # El reserve es un conteo de cartuchos: el cargador retirado vuelve al pool.
    var pool := reserve + mag
    var loaded := mini(MAG_SIZE, pool)
    reserve = pool - loaded
    mag = loaded
    reload_mag_seated = true
    _emit_ammo()


func _finish_reload() -> void:
    if not reload_mag_seated:
        _seat_reload_mag()
    reloading = false
    mag_inserted_sound = false
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

    var look_x := clampf(look_delta.x, -12.0, 12.0) * 0.0015
    var look_y := clampf(look_delta.y, -12.0, 12.0) * 0.0015
    sway.x += (-look_x - sway.x) * (1.0 - exp(-10.0 * delta))
    sway.y += (-look_y - sway.y) * (1.0 - exp(-10.0 * delta))
    sway.x = clampf(sway.x, -0.012, 0.012)
    sway.y = clampf(sway.y, -0.012, 0.012)

    if player_speed > 0.25:
        bob_phase += delta * (1.8 + player_speed * 1.45)

    var hip_pos := HIP_POS
    var ads_pos := ads_offset
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
    var move_x := clampf(_last_local_move.x, -1.0, 1.0)
    var move_y := clampf(_last_local_move.y, -1.0, 1.0)
    pos.x -= move_x * 0.02 * (1.0 - aim_blend * 0.5)
    pos.y -= absf(move_y) * 0.008 * (1.0 - aim_blend * 0.5)

    rot.x += sway.y * 0.5 + sin(idle_phase * 1.05) * 0.0025 * (1.0 - aim_blend * 0.6) - move_y * 0.008
    rot.y += sway.x * 0.5 + sin(idle_phase * 0.73 + 1.0) * 0.0020 * (1.0 - aim_blend * 0.6)
    rot.z += -move_x * 0.012 - sin(bob_phase) * 0.012 * sprint_blend
    pos.x = clampf(pos.x, -0.30, 0.30)
    pos.y = clampf(pos.y, -0.30, 0.18)
    pos.z = clampf(pos.z, -0.20, 0.15)
    rot.x = clampf(rot.x, -0.35, 0.35)
    rot.y = clampf(rot.y, -0.35, 0.35)
    rot.z = clampf(rot.z, -0.25, 0.25)

    # Recarga: el arma sube un poco hacia la cámara y se ladea para que se vea el
    # cargador salir y entrar. Antes caía hacia abajo y se iba de pantalla.
    pos.y += reload_pose_blend * 0.05
    pos.z += reload_pose_blend * 0.05
    rot.x += reload_pose_blend * 0.22
    rot.z -= reload_pose_blend * 0.16
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
    # Un poco más grande que el real para que se vea en primera persona.
    shell_mesh.scale = Vector3(1.35, 1.0, 1.35)
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
    # El puerto está en la cara derecha del arma: el casquillo sale a la derecha
    # (+X), arriba (+Y) y algo hacia atrás (+Z, que es la cola del arma).
    var local_vel := Vector3(2.2 + randf() * 1.2, 1.9 + randf() * 0.9, 0.6 + randf() * 0.7)
    shell.linear_velocity = basis * local_vel + player_velocity * 0.8
    shell.angular_velocity = Vector3(randf_range(-26.0, 26.0), randf_range(-26.0, 26.0), randf_range(-26.0, 26.0))


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
    brass_mat.albedo_color = Color(0.78, 0.55, 0.16)
    brass_mat.metallic = 1.0
    brass_mat.roughness = 0.28
    brass_mat.emission_enabled = true
    brass_mat.emission = Color(0.25, 0.08, 0.01)
    brass_mat.emission_energy_multiplier = 0.5

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
    if packed == null:
        push_error("No se pudo cargar el modelo Glock riggeado")
        return
    model_root = packed.instantiate()
    model_root.name = "GlockModel"
    model_root.transform = Transform3D.IDENTITY
    recoil_node.add_child(model_root)

    skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
    glock_mesh = model_root.find_child("Glock19", true, false) as MeshInstance3D
    var bullet_mesh := model_root.find_child("Glock19_001", true, false) as MeshInstance3D
    if bullet_mesh != null:
        bullet_mesh.visible = false
    _apply_model_materials()

    # El GLB no viene alineado con los ejes de Godot: el nodo Armature trae su
    # propia rotación y los bind poses otra distinta. En vez de suponer cuál es
    # la orientación "correcta", se mide la geometría real en runtime y se
    # corrige el modelo con esa medida (ver _measure_mesh).
    var measure := _measure_mesh()
    if measure.get("ok", false):
        _align_model_with_mesh(measure)
        _build_reference_markers(measure)
    else:
        # Sin medida fiable no se inventa orientación: se avisa y se dejan los
        # marcadores en las cotas nominales de una Glock 19.
        push_error("No se pudo medir la malla del Glock: se usan cotas nominales")
        _build_reference_markers({})

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


## Mide la malla tal como viene del GLB: vértices en su espacio de bind, caja
## envolvente y base real del arma. No se asume ninguna orientación: el eje más
## largo de la malla es el del cañón, el mediano la altura (corredera arriba,
## empuñadura abajo) y el más corto la anchura. Los signos salen de la propia
## geometría, porque la empuñadura está en la mitad trasera y cuelga hacia abajo.
func _measure_mesh() -> Dictionary:
    var verts := PackedVector3Array()
    if glock_mesh != null and glock_mesh.mesh != null:
        for surface in range(glock_mesh.mesh.get_surface_count()):
            var arrays := glock_mesh.mesh.surface_get_arrays(surface)
            if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
                continue
            verts.append_array(arrays[Mesh.ARRAY_VERTEX])
    var measure := {"ok": false, "verts": verts, "frame": Basis.IDENTITY, "length": 1.0, "aabb": AABB()}
    if verts.is_empty():
        push_error("La malla del Glock no tiene vértices: imposible medir su base")
        return measure

    var mn := verts[0]
    var mx := verts[0]
    for v in verts:
        mn = mn.min(v)
        mx = mx.max(v)
    var size := mx - mn

    var axes := [0, 1, 2]
    axes.sort_custom(func(a, b): return size[a] > size[b])
    var axis_len: int = axes[0]
    var axis_up: int = axes[1]

    # Rango vertical de cada mitad a lo largo del cañón.
    var mid := mn[axis_len] + size[axis_len] * 0.5
    var front_lo := INF
    var front_hi := -INF
    var rear_lo := INF
    var rear_hi := -INF
    for v in verts:
        if v[axis_len] <= mid:
            front_lo = minf(front_lo, v[axis_up])
            front_hi = maxf(front_hi, v[axis_up])
        else:
            rear_lo = minf(rear_lo, v[axis_up])
            rear_hi = maxf(rear_hi, v[axis_up])

    # La mitad con más altura es la trasera (empuñadura + cargador).
    var back_sign := 1.0 if (rear_hi - rear_lo) > (front_hi - front_lo) else -1.0
    # La empuñadura sobresale por debajo de la línea del cañón: la trasera baja
    # mucho más de lo que sube, así que "arriba" es el lado contrario.
    var up_sign := 1.0 if (front_lo - rear_lo) > (rear_hi - front_hi) else -1.0

    var forward := Vector3.ZERO
    forward[axis_len] = -back_sign
    var up := Vector3.ZERO
    up[axis_up] = up_sign
    var right := up.cross(-forward)

    measure["frame"] = Basis(right, up, -forward)
    measure["length"] = size[axis_len]
    measure["aabb"] = AABB(mn, size)
    measure["ok"] = true
    return measure


## Corrige model_root para que la malla quede en el frame del arma:
## -Z adelante (boca), +Y arriba (corredera) y +X derecha, con la escala real
## (Glock 19 = 186 mm de largo). La corrección sale de la cadena medida
## hueso/bind/armature, no de números fijos.
func _align_model_with_mesh(measure: Dictionary) -> void:
    if model_root == null or skeleton == null or glock_mesh == null or glock_mesh.skin == null:
        push_error("No se pudo medir la base del arma: falta esqueleto o skin")
        return
    # El nodo de malla cuelga del Skeleton3D con transform identidad; los bind
    # poses llevan del espacio de bind al del esqueleto.
    bind_in_skeleton = skeleton.get_bone_global_rest(0) * glock_mesh.skin.get_bind_pose(0)
    var bind_in_model: Transform3D = _local_chain(skeleton, model_root) * bind_in_skeleton

    var length_bind: float = maxf(measure["length"], 0.000001)
    var total_scale: float = GUN_LENGTH / length_bind
    gun_frame_bind = measure["frame"]

    # model_root * (bind -> modelo) * frame_bind = escala uniforme (sin rotación).
    model_root.basis = Basis.IDENTITY.scaled(Vector3.ONE * total_scale) * (bind_in_model.basis * gun_frame_bind).inverse()
    model_root.position = Vector3.ZERO
    mesh_to_weapon = model_root.transform * bind_in_model
    model_units_per_meter = 1.0 / total_scale
    _verify_alignment()
    print("GLOCK_MEDIDA largo_bind=", snappedf(length_bind, 0.000001),
        " escala=", snappedf(total_scale, 0.001),
        " frame_bind=", gun_frame_bind.orthonormalized().get_euler().snapped(Vector3(0.001, 0.001, 0.001)),
        " largo_m=", snappedf(length_bind * total_scale, 0.0001))


## Comprobación en runtime de que la corrección quedó bien: la malla tiene que
## quedar en el frame del arma (base uniforme, sin rotación) y con la mano
## correcta (en una Glock el cierre de corredera va al lado izquierdo).
func _verify_alignment() -> void:
    var check := mesh_to_weapon.basis * gun_frame_bind
    var residual := check.orthonormalized()
    var error := 0.0
    for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
        error = maxf(error, (residual * axis - axis).length())
    var scale := check.get_scale()
    var shear := maxf(maxf(absf(scale.x - scale.y), absf(scale.y - scale.z)), absf(scale.x - scale.z))
    if error > 0.002 or shear > 0.002:
        push_error("Alineación del Glock incorrecta: residual=%s escala=%s" % [residual, scale])
    if skeleton == null:
        return
    var catch_bone := skeleton.find_bone("SlideCatch")
    if catch_bone >= 0 and (mesh_to_weapon * _bone_origin_in_bind(catch_bone)).x > 0.0:
        push_warning("La mano del modelo quedó espejada: el cierre de corredera sale a la derecha")


## Origen de un hueso expresado en el espacio de bind de la malla.
func _bone_origin_in_bind(bone: int) -> Vector3:
    return bind_in_skeleton.affine_inverse() * skeleton.get_bone_global_rest(bone).origin


## Transformación local acumulada de `node` hasta su ancestro `ancestor`.
func _local_chain(node: Node, ancestor: Node) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current := node
    while current != null and current != ancestor:
        if current is Node3D:
            result = (current as Node3D).transform * result
        current = current.get_parent()
    return result


## Coloca boca, mira y puerto de expulsión midiendo la geometría ya alineada.
## Cuelgan de un nodo en el frame del arma (metros), no del modelo: así no
## heredan la rotación interna del GLB y sus medidas siguen siendo válidas.
func _build_reference_markers(measure: Dictionary) -> void:
    gun_frame = Node3D.new()
    gun_frame.name = "GunFrame"
    recoil_node.add_child(gun_frame)

    muzzle = Node3D.new()
    muzzle.name = "Muzzle"
    gun_frame.add_child(muzzle)

    sight_marker = Node3D.new()
    sight_marker.name = "SightReference"
    gun_frame.add_child(sight_marker)

    ejection_port = Node3D.new()
    ejection_port.name = "EjectionPort"
    gun_frame.add_child(ejection_port)

    if measure.is_empty():
        # Cotas nominales de una Glock 19 (metros) si la medida falló.
        muzzle.position = Vector3(0.0, 0.015, -0.090)
        sight_marker.position = Vector3(0.0, 0.035, 0.060)
        ejection_port.position = Vector3(0.012, 0.022, 0.010)
        _build_flash()
        return

    var verts: PackedVector3Array = measure["verts"]
    var weapon_verts := PackedVector3Array()
    weapon_verts.resize(verts.size())
    for i in range(verts.size()):
        weapon_verts[i] = mesh_to_weapon * verts[i]
    var box := _bounds(weapon_verts)

    # Corona del cañón: centroide de la banda delantera de la malla.
    muzzle.position = _band_centroid(weapon_verts, box, 0.0, 0.04, 0.0, 1.0)
    # Mira trasera: lo más alto de la corredera en la banda trasera.
    sight_marker.position = _band_centroid(weapon_verts, box, 0.80, 1.0, 0.90, 1.0)
    # Puerto de expulsión: cara derecha de la corredera, a media longitud.
    ejection_port.position = _ejection_point(weapon_verts, box)
    _build_flash()


## Puerto de expulsión medido: cara derecha (+X) de la corredera entre el 35% y
## el 65% de la longitud, a la altura de la corredera.
func _ejection_point(verts: PackedVector3Array, box: AABB) -> Vector3:
    var z_min := box.position.z + box.size.z * 0.35
    var z_max := box.position.z + box.size.z * 0.65
    var y_min := box.position.y + box.size.y * 0.60
    var face := -INF
    for v in verts:
        if v.z < z_min or v.z > z_max or v.y < y_min:
            continue
        face = maxf(face, v.x)
    if face == -INF:
        return Vector3(0.0, box.position.y + box.size.y * 0.7, box.position.z + box.size.z * 0.5)
    var sum := Vector3.ZERO
    var count := 0
    for v in verts:
        if v.z < z_min or v.z > z_max or v.y < y_min or v.x < face - 0.004:
            continue
        sum += v
        count += 1
    var centre := sum / float(maxi(count, 1))
    # 4 mm dentro de la cara: el casquillo nace en el puerto, no pegado al aire.
    return Vector3(face - 0.004, centre.y, centre.z)


func _bounds(verts: PackedVector3Array) -> AABB:
    if verts.is_empty():
        return AABB()
    var mn := verts[0]
    var mx := verts[0]
    for v in verts:
        mn = mn.min(v)
        mx = mx.max(v)
    return AABB(mn, mx - mn)


## Centroide de los vértices dentro de una banda de la caja: `z0`/`z1` y `y0`/`y1`
## son fracciones de la longitud (boca -> culata) y de la altura (abajo -> arriba).
func _band_centroid(verts: PackedVector3Array, box: AABB, z0: float, z1: float, y0: float, y1: float) -> Vector3:
    var z_min := box.position.z + box.size.z * z0
    var z_max := box.position.z + box.size.z * z1
    var y_min := box.position.y + box.size.y * y0
    var y_max := box.position.y + box.size.y * y1
    var sum := Vector3.ZERO
    var count := 0
    for v in verts:
        if v.z < z_min or v.z > z_max or v.y < y_min or v.y > y_max:
            continue
        sum += v
        count += 1
    if count == 0:
        return sum
    return sum / float(count)


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


func _compute_ads_offset() -> void:
    if sight_marker == null or camera == null:
        return
    # Posición del marcador de mira dentro del espacio local del arma (con pose cero).
    sight_marker.force_update_transform()
    force_update_transform()
    camera.force_update_transform()
    var p_rel := global_transform.affine_inverse() * sight_marker.global_position
    # Transformación cámara -> arma (incluye el offset/rotación del WeaponRig).
    var cam_from_glock := camera.global_transform.affine_inverse() * global_transform
    # La mira trasera medida se lleva al centro de la pantalla a distancia real
    # de tiro con pistola (brazo extendido); antes el marcador estaba mal medido
    # y el arma quedaba pegada a la cámara.
    var desired_cam := Vector3(0.0, -ADS_SIGHT_DROP, -ADS_SIGHT_DISTANCE)
    ads_offset = cam_from_glock.affine_inverse() * desired_cam - p_rel


func get_sight_world_position() -> Vector3:
    if sight_marker != null:
        return sight_marker.global_position
    return global_position


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
        # Direcciones reales del arma medidas sobre la malla y llevadas al
        # espacio del hueso: la corredera abre hacia atrás y el cargador baja.
        # No se asume que el GLB esté alineado con los ejes de Godot.
        var back_skel := (bind_in_skeleton.basis * gun_frame_bind.z).normalized()
        var down_skel := (bind_in_skeleton.basis * -gun_frame_bind.y).normalized()
        slide_axis = (inverse_root * back_skel).normalized()
        magazine_axis = (inverse_root * down_skel).normalized()


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
        skeleton.set_bone_pose_rotation(bone_trigger, trigger_basis.get_rotation_quaternion())


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
