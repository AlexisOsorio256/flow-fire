extends Node3D

signal shot_fired
signal ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool)

## AUTORIDAD MECANICA del arma: el estado fisico de la pistola.
##
## Aqui viven municion, recamara, gatillo, cadencia, corredera, recarga y los
## eventos fisicos (disparo, extraccion, asiento del cargador). Nada mas.
##
## La presentacion esta fuera y NO tiene copia de este estado:
##   scripts/GlockViewmodel.gd  rig, huesos, ADS, pose, materiales, animacion
##   scripts/GlockRecoil.gd     resortes de retroceso y su transform
##   scripts/WeaponFX.gd        fogonazo, luz de boca y humo
## Glock los compone y les PASA el estado ya decidido; ellos lo representan.
const MAG_SIZE := 17
const SLIDE_TRAVEL := 0.039
const SLIDE_K := 4000.0
const SLIDE_C := 80.0
const SLIDE_IMPULSE := 6.50
const SLIDE_RESTITUTION := 0.25
const SLIDE_EJECT_AT := 0.030

# Tiempos vistos en la grabacion del usuario. El magout anterior (0.10 s)
# sonaba mientras el cargador seguia dentro; el contacto visible empieza cerca
# de medio segundo. El asiento ya coincidia razonablemente y se conserva.
const RELOAD_MAG_OUT_T := 0.48
const RELOAD_TACTICAL_MAG_IN_T := 2.25
const RELOAD_EMPTY_MAG_IN_T := 3.36
const RELOAD_SLIDE_T := 2.87
const RELOAD_EMPTY_TOTAL := 4.00
const RELOAD_TACTICAL_TOTAL := 3.20
const RELOAD_POSE_START := 0.34
const RELOAD_POSE_RISE := 0.52
const RELOAD_POSE_FALL := 0.42

# Correccion del staging del clip tactico. El asset deja Magazine_924 flotando
# aproximadamente un segundo. Se usa LA MANO IZQUIERDA DEL MISMO RIG: antes de
# reproducir el clip se muestrea una pose donde ya sostiene el cargador y se
# guarda el transform mano->cargador. Durante el hueco se mezcla hacia esa
# relacion rigida; antes del asiento se devuelve suavemente a la pista original.
const RELOAD_MAG_PICKUP_SAMPLE_T := 2.02
const RELOAD_MAG_CARRY_START := 1.05
const RELOAD_MAG_CARRY_FULL := 1.38
const RELOAD_MAG_RETURN_START := 2.02
const RELOAD_MAG_RETURN_END := 2.24

# Inspect (clip ~5.2 s). En el video el foley existia en codigo, pero quedaba
# perceptualmente enterrado.
const INSPECT_GRAB_T := 0.90
const INSPECT_SHIFT_T := 2.25
const INSPECT_SLIDE_GRAB_T := 3.15
const INSPECT_SLIDE_HOME_T := 4.12
const INSPECT_TOTAL := 5.30

# --- Estado mecanico -------------------------------------------------------
var camera: Camera3D
var viewmodel: GlockViewmodel
var recoil: GlockRecoil
var fx: WeaponFX

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
var slide_open := false
var slide_rear_sound_emitted := true
var slide_battery_emitted := true
var trigger_visual := 0.0

var reloading := false
var reload_elapsed := 0.0
var reload_total := 0.0
var reload_empty := false
var reload_slide_released := false
var reload_mag_seated := false
var mag_sound_out := false
var reload_pose_blend := 0.0

# Estado de la correccion mano<->cargador. No es gameplay: solo una relacion
# espacial de presentacion para reparar un tramo defectuoso del asset.
var _reload_left_hand_bone := -1
var _reload_mag_hand_offset := Transform3D.IDENTITY
var _reload_mag_carry_ready := false

var inspecting := false
var inspect_elapsed := 0.0
var inspect_grab := false
var inspect_shift := false
var inspect_slide_grab := false
var inspect_slide_home := false

# --- Entradas de gameplay --------------------------------------------------
var aim := false
var sprinting := false
var aim_blend := 0.0
var sprint_blend := 0.0
var player_speed := 0.0
var look_delta := Vector2.ZERO
var player_velocity := Vector3.ZERO
var _last_local_move := Vector2.ZERO

var shot_pulse := 0.0


func _ready() -> void:
	recoil = GlockRecoil.new()
	viewmodel = GlockViewmodel.new()
	viewmodel.name = "Viewmodel"
	viewmodel.recoil = recoil
	add_child(viewmodel)
	viewmodel.mount()
	if viewmodel.muzzle != null:
		fx = WeaponFX.new()
		fx.name = "WeaponFX"
		viewmodel.muzzle.add_child(fx)
		fx.build()
	if camera != null and viewmodel.arms_ok and not viewmodel.ads_solved:
		camera.force_update_transform()
		viewmodel.solve_ads()
	_emit_ammo()


func setup(cam: Camera3D) -> void:
	camera = cam
	viewmodel.setup(cam)


func _update_aim(delta: float) -> void:
	var target_sprint := 1.0 if sprinting else 0.0
	sprint_blend += (target_sprint - sprint_blend) * (1.0 - exp(-5.5 * delta))
	var target_aim := (1.0 if aim else 0.0) * (1.0 - sprint_blend)
	aim_blend += (target_aim - aim_blend) * (1.0 - exp(-9.0 * delta))


func _process(delta: float) -> void:
	_update_aim(delta)
	_update_trigger(delta)
	_update_slide(delta)
	_update_reload(delta)
	_update_inspect(delta)
	recoil.update(delta)
	viewmodel.set_pose_inputs(aim_blend, sprint_blend, player_speed, look_delta, _last_local_move, reload_pose_blend)
	viewmodel.update(delta)
	viewmodel.apply_mechanics(slide_pos, SLIDE_TRAVEL, trigger_visual, not slide_locked and slide_pos < 0.02)
	# AnimationPlayer vive dentro del rig y puede escribir sus huesos despues del
	# proceso del padre. Aplicar el carry diferido garantiza que la correccion se
	# compone SOBRE la pose animada del frame, no pelea contra ella.
	if reloading and not reload_empty and _reload_mag_carry_ready:
		call_deferred("_apply_reload_mag_carry")

	shot_pulse = maxf(0.0, shot_pulse - delta * 8.0)
	if fx != null:
		fx.update(delta)


func set_aim(value: bool) -> void:
	aim = value


func set_sprint(value: bool) -> void:
	sprinting = value


func set_motion(speed: float, local_move: Vector2, look: Vector2) -> void:
	player_speed = speed
	look_delta = look
	_last_local_move = local_move


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
	inspecting = false
	reload_elapsed = 0.0
	reload_empty = chamber <= 0
	reload_total = RELOAD_EMPTY_TOTAL if reload_empty else RELOAD_TACTICAL_TOTAL
	reload_slide_released = false
	reload_mag_seated = false
	mag_sound_out = false
	reload_pose_blend = 0.0
	aim = false
	trigger_held = false

	_reload_mag_carry_ready = false
	if not reload_empty:
		_prepare_reload_mag_carry()
	viewmodel.play_reload(reload_empty)
	_emit_ammo()
	return true


## Busca la mano izquierda sin depender del sufijo numerico del importador.
## El rig conocido usa nombres Blender tipo DEF-hand.R_842; se favorece DEF + L.
func _find_left_hand_bone() -> int:
	if viewmodel == null or viewmodel.arms_skeleton == null:
		return -1
	var sk: Skeleton3D = viewmodel.arms_skeleton
	var best := -1
	var best_score := -1
	for i in range(sk.get_bone_count()):
		var name := sk.get_bone_name(i).to_lower()
		if not name.contains("hand"):
			continue
		var left := name.contains(".l") or name.contains("_l") or name.contains("-l") or name.contains("left")
		if not left:
			continue
		var score := 1
		if name.contains("def"):
			score += 4
		if name.begins_with("def-hand"):
			score += 3
		if score > best_score:
			best = i
			best_score = score
	return best


## Muestra el propio clip en una pose donde la mano ya agarro el cargador y
## obtiene la relacion mano->mag. Inmediatamente despues start_reload reproduce
## el clip desde cero, asi que esta medicion nunca aparece en pantalla.
func _prepare_reload_mag_carry() -> void:
	if viewmodel == null or viewmodel.arms_player == null or viewmodel.arms_skeleton == null:
		return
	if viewmodel.mag_bone < 0:
		return
	_reload_left_hand_bone = _find_left_hand_bone()
	if _reload_left_hand_bone < 0:
		return
	var clip := viewmodel._resolve_clip("Reload")
	if clip == "":
		return
	var player: AnimationPlayer = viewmodel.arms_player
	var sk: Skeleton3D = viewmodel.arms_skeleton
	player.play(clip)
	player.seek(RELOAD_MAG_PICKUP_SAMPLE_T, true)
	sk.force_update_all_bone_transforms()
	var hand_global: Transform3D = sk.get_bone_global_pose(_reload_left_hand_bone)
	var mag_global: Transform3D = sk.get_bone_global_pose(viewmodel.mag_bone)
	_reload_mag_hand_offset = hand_global.affine_inverse() * mag_global
	_reload_mag_carry_ready = true


## Re-coreografia SOLO el hueco defectuoso de Reload. La pose original del
## cargador se conserva en los extremos; en medio se mezcla hacia la mano con
## la relacion medida del propio clip. No se inventa un offset manual.
func _apply_reload_mag_carry() -> void:
	if not reloading or reload_empty or not _reload_mag_carry_ready:
		return
	if reload_elapsed < RELOAD_MAG_CARRY_START or reload_elapsed > RELOAD_MAG_RETURN_END:
		return
	if viewmodel == null or viewmodel.arms_skeleton == null or viewmodel.mag_bone < 0:
		return
	var sk: Skeleton3D = viewmodel.arms_skeleton
	if _reload_left_hand_bone < 0 or _reload_left_hand_bone >= sk.get_bone_count():
		return

	sk.force_update_all_bone_transforms()
	var hand_global: Transform3D = sk.get_bone_global_pose(_reload_left_hand_bone)
	var desired_global: Transform3D = hand_global * _reload_mag_hand_offset
	var parent := sk.get_bone_parent(viewmodel.mag_bone)
	var desired_local := desired_global
	if parent >= 0:
		desired_local = sk.get_bone_global_pose(parent).affine_inverse() * desired_global

	var acquire := clampf((reload_elapsed - RELOAD_MAG_CARRY_START) / maxf(RELOAD_MAG_CARRY_FULL - RELOAD_MAG_CARRY_START, 0.001), 0.0, 1.0)
	var release := clampf((reload_elapsed - RELOAD_MAG_RETURN_START) / maxf(RELOAD_MAG_RETURN_END - RELOAD_MAG_RETURN_START, 0.001), 0.0, 1.0)
	var weight := _smooth(acquire) * (1.0 - _smooth(release))
	if weight <= 0.0001:
		return

	var current_pos := sk.get_bone_pose_position(viewmodel.mag_bone)
	var current_rot := sk.get_bone_pose_rotation(viewmodel.mag_bone)
	var desired_rot := desired_local.basis.get_rotation_quaternion().normalized()
	sk.set_bone_pose_position(viewmodel.mag_bone, current_pos.lerp(desired_local.origin, weight))
	sk.set_bone_pose_rotation(viewmodel.mag_bone, current_rot.slerp(desired_rot, weight))


func _can_fire() -> bool:
	return not reloading and chamber > 0 and absf(slide_pos) < 0.0025


func _update_trigger(delta: float) -> void:
	trigger_visual += ((1.0 if trigger_held else 0.0) - trigger_visual) * (1.0 - exp(-18.0 * delta))
	if trigger_held and trigger_ready and _can_fire():
		_fire()
		return
	if trigger_held and trigger_ready and not reloading and chamber <= 0 and not slide_locked:
		trigger_ready = false
		trigger_latched = true
		trigger_reset_timer = 0.075
		GameAudio.play_2d("empty")
	if not trigger_held:
		if trigger_latched:
			trigger_reset_timer -= delta
			if trigger_reset_timer <= 0.0:
				trigger_ready = true
				trigger_latched = false
				GameAudio.play_2d("slide_hand", -8.0, randf_range(1.25, 1.35))
		else:
			trigger_ready = true


func _fire() -> void:
	chamber -= 1
	inspecting = false
	trigger_ready = false
	trigger_latched = true
	trigger_reset_timer = 0.075
	slide_extracted = false
	slide_open = false
	slide_rear_sound_emitted = false
	slide_battery_emitted = false
	slide_vel += SLIDE_IMPULSE
	shot_pulse = 1.0
	recoil.kick_shot()
	GameAudio.play_shot()
	viewmodel.play_fire()

	var origin := viewmodel.muzzle.global_position
	var cam_fwd := -camera.global_transform.basis.z.normalized()
	var aim_point := camera.global_position + cam_fwd * 46.0
	var dir := (aim_point - origin).normalized()
	var right := camera.global_transform.basis.x.normalized()
	var up := camera.global_transform.basis.y.normalized()
	var move_amount := clampf(player_speed / 4.35, 0.0, 1.0)
	var spread := 0.00055 if aim_blend > 0.55 else 0.0036 + move_amount * 0.0052
	dir = (dir + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()
	Ballistics.fire(origin, dir, 372.0, 0.42)
	fx.fire(origin, cam_fwd)
	emit_signal("shot_fired")
	_emit_ammo()


func _update_slide(delta: float) -> void:
	if slide_locked:
		slide_pos = SLIDE_TRAVEL
		slide_vel = 0.0
	else:
		const SUBSTEP := 0.0025
		var span := minf(delta, SUBSTEP * 64.0)
		var steps := maxi(1, ceili(span / SUBSTEP))
		var h := span / float(steps)
		for _i in range(steps):
			slide_vel += (-SLIDE_K * slide_pos - SLIDE_C * slide_vel) * h
			slide_pos += slide_vel * h
			if slide_pos < 0.0:
				slide_pos = 0.0
				slide_vel = maxf(0.0, slide_vel)
			if slide_pos > SLIDE_TRAVEL:
				slide_pos = SLIDE_TRAVEL
				slide_vel = -slide_vel * SLIDE_RESTITUTION
				_emit_slide_rear_event()
			if not slide_extracted and slide_pos > SLIDE_EJECT_AT:
				slide_extracted = true
				_spawn_shell()
			if slide_pos > 0.02:
				slide_open = true
			if slide_open and not slide_battery_emitted and slide_pos <= 0.004 and slide_vel <= 0.0:
				slide_battery_emitted = true
				GameAudio.play_2d("slide_battery", 0.0, randf_range(0.97, 1.03))
			if slide_open and slide_pos <= 0.001 and chamber <= 0 and mag > 0:
				slide_open = false
				mag -= 1
				chamber = 1
				_emit_ammo()
	if slide_pos > SLIDE_TRAVEL * 0.87 and mag <= 0 and chamber <= 0 and not reloading:
		slide_locked = true
		slide_pos = SLIDE_TRAVEL
		slide_vel = 0.0
		_emit_slide_rear_event()


func _emit_slide_rear_event() -> void:
	if slide_rear_sound_emitted:
		return
	slide_rear_sound_emitted = true
	GameAudio.play_2d("slide_rear", 0.0, randf_range(0.98, 1.06))


func _update_reload(delta: float) -> void:
	if not reloading:
		return
	reload_elapsed += delta
	if not mag_sound_out and reload_elapsed >= RELOAD_MAG_OUT_T:
		mag_sound_out = true
		GameAudio.play_2d("magout", 1.0, randf_range(0.96, 1.03))

	var mag_in_t: float = RELOAD_EMPTY_MAG_IN_T if reload_empty else RELOAD_TACTICAL_MAG_IN_T
	if not reload_mag_seated and reload_elapsed >= mag_in_t:
		_seat_reload_mag()
		recoil.kick_mag_seat()
		GameAudio.play_2d("magin", 1.0, randf_range(0.96, 1.03))

	if reload_empty and not reload_slide_released and reload_elapsed >= RELOAD_SLIDE_T:
		reload_slide_released = true
		slide_locked = false
		slide_pos = SLIDE_TRAVEL
		slide_vel = -4.2
		slide_battery_emitted = false
		GameAudio.play_2d("slide_hand", 0.0, randf_range(0.98, 1.04))

	var up_t := clampf((reload_elapsed - RELOAD_POSE_START) / RELOAD_POSE_RISE, 0.0, 1.0)
	var down_t := clampf((reload_elapsed - (mag_in_t + 0.06)) / RELOAD_POSE_FALL, 0.0, 1.0)
	reload_pose_blend = _smooth(up_t) * (1.0 - _smooth(down_t))
	if reload_elapsed >= reload_total:
		_finish_reload()


func inspect_weapon() -> void:
	if reloading:
		return
	inspecting = true
	inspect_elapsed = 0.0
	inspect_grab = false
	inspect_shift = false
	inspect_slide_grab = false
	inspect_slide_home = false
	viewmodel.play_anim("Inspect")


func _update_inspect(delta: float) -> void:
	if not inspecting:
		return
	inspect_elapsed += delta
	if not inspect_grab and inspect_elapsed >= INSPECT_GRAB_T:
		inspect_grab = true
		GameAudio.play_2d("handling", 6.0, randf_range(0.98, 1.02))
	if not inspect_shift and inspect_elapsed >= INSPECT_SHIFT_T:
		inspect_shift = true
		GameAudio.play_2d("handling", 3.0, randf_range(1.02, 1.07))
	if not inspect_slide_grab and inspect_elapsed >= INSPECT_SLIDE_GRAB_T:
		inspect_slide_grab = true
		GameAudio.play_2d("slide_hand", 5.0, randf_range(0.99, 1.03))
	if not inspect_slide_home and inspect_elapsed >= INSPECT_SLIDE_HOME_T:
		inspect_slide_home = true
		GameAudio.play_2d("slide_battery", 3.0, randf_range(0.99, 1.02))
	if inspect_elapsed >= INSPECT_TOTAL:
		inspecting = false


func _seat_reload_mag() -> void:
	if reload_mag_seated:
		return
	var pool := reserve + mag
	var loaded := mini(MAG_SIZE, pool)
	reserve = pool - loaded
	mag = loaded
	reload_mag_seated = true
	_emit_ammo()


func _finish_reload() -> void:
	if not reload_mag_seated:
		_seat_reload_mag()
	if reload_empty and chamber <= 0 and mag > 0:
		mag -= 1
		chamber = 1
	reloading = false
	reload_pose_blend = 0.0
	_reload_mag_carry_ready = false
	viewmodel.blend_to_idle(0.14)
	_emit_ammo()


func _spawn_shell() -> void:
	if not is_instance_valid(get_tree().current_scene):
		return
	Shell.spawn(get_tree().current_scene, viewmodel.ejection_port.global_transform, slide_vel, player_velocity)


func _emit_ammo() -> void:
	ammo_changed.emit(mag, chamber, reserve, reloading)


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)