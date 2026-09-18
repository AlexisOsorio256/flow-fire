extends Node3D

signal shot_fired
signal ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool)

## AUTORIDAD MECANICA del arma: el estado fisico de la pistola.
##
## Aqui viven municion, recamara, gatillo, cadencia, corredera, recarga y los
## eventos fisicos (disparo, extraccion, asiento del cargador, agarre del
## cargador). Nada mas.
##
## La presentacion esta fuera y NO tiene copia de este estado:
##   scripts/GlockViewmodel.gd  rig, brazos, animacion, pose, sockets
##   scripts/GlockWeapon.gd     las PIEZAS del arma (corredera, gatillo, cargador)
##   scripts/GlockRecoil.gd     retroceso y peso
##   scripts/WeaponFX.gd        fogonazo, luz de boca y humo
## Glock los compone y les PASA el estado ya decidido; ellos lo representan.
##
## EL ARMA NO ESTA EN EL ESQUELETO. Es un arbol de piezas (GlockWeapon), asi que
## mover la corredera o el cargador es escribir un transform, no una pose de
## hueso.
##
## LOS INSTANTES SON DEL CLIP. Esta pistola se anima con clips que no escribimos
## nosotros, asi que los eventos de la recarga (`RELOAD_*_T`) y de la inspeccion
## (`INSPECT_*_T`) son los tiempos de sus gestos, medidos una vez con
## `tools/check_reload.gd` y escritos aqui al lado. Si un dia se cambia o se
## retoca un clip, se vuelven a medir con la herramienta: no hay nada que
## adivinar y nada que se desincronice solo.

## Capacidad del cargador: la fija el arma (GlockWeapon.CARGADOR) al montar.
var MAG_SIZE := 17
## Recorrido de la corredera en metros reales. La autoridad es el arma
## (GlockWeapon.corredera); aqui se copia al montar.
var _travel := GlockWeapon.CORREDERA
## Corredera: rigidez y amortiguacion del resorte, y en FRACCION del recorrido
## donde pasa cada cosa. Asi el unico numero que describe el arma es su recorrido.
const SLIDE_K := 4000.0
const SLIDE_C := 80.0
const SLIDE_IMPULSE := 6.50
const SLIDE_RESTITUTION := 0.25
const SLIDE_EJECT_AT := 0.77      # ya salio la vaina
const SLIDE_OPEN_AT := 0.51       # la corredera esta abierta
const SLIDE_BATTERY_AT := 0.10    # ya volvio a bateria
const SLIDE_CLOSED_AT := 0.026    # cerrada del todo
## 9x19 de la Glock 19: punta de 115 granos a ~372 m/s. `TRAZADORA` es la
## fraccion de balas que sale trazadora.
const BALA_VELOCIDAD := 372.0
const BALA_TRAZADORA := 0.42

## Duracion de cada recarga: un pelo mas que su clip (`Reload` 3,33 s,
## `Reload_Empty` 2,93 s), para que las manos ya hayan vuelto a idle cuando la
## mecanica termina.
const RELOAD_TOTAL := 3.45
const RELOAD_EMPTY_TOTAL := 3.05
## Recarga en seco: instante del clip en el que la mano suelta la corredera.
const RELOAD_SLIDE_T := 2.15
## Los DOS instantes de cada clip de recarga en los que el cargador cambia de
## mano: cuando la mano izquierda se lo lleva y cuando lo deja en el brocal. Son
## los dos minimos de la distancia mano<->brocal, medidos en el clip.
const RELOAD_MAG_OUT_T := 0.24
const RELOAD_MAG_IN_T := 3.27
const RELOAD_EMPTY_MAG_OUT_T := 0.15
const RELOAD_EMPTY_MAG_IN_T := 2.80
## Instantes del clip Inspect (3.73 s en este pack).
const INSPECT_TOTAL := 3.85
const INSPECT_GRAB_T := 0.64
const INSPECT_SHIFT_T := 1.61
const INSPECT_SLIDE_GRAB_T := 2.26
const INSPECT_SLIDE_HOME_T := 2.95

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
var reload_pose_blend := 0.0

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

# --- Cargador: eventos medidos, no cronometrados ---------------------------
var _mag_grab_done := false
var _mag_handoff_done := false


func _ready() -> void:
	recoil = GlockRecoil.new()
	viewmodel = GlockViewmodel.new()
	viewmodel.name = "Viewmodel"
	viewmodel.recoil = recoil
	add_child(viewmodel)
	viewmodel.mount()
	if viewmodel.weapon != null:
		MAG_SIZE = viewmodel.weapon.capacidad
		_travel = viewmodel.weapon.corredera
		mag = MAG_SIZE
		reserve = MAG_SIZE * 4
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
	# El arma dibuja el estado ya decidido: una sola direccion, sin correcciones
	# posteriores sobre el esqueleto ni sobre los huesos de nadie.
	if viewmodel.weapon != null:
		viewmodel.weapon.set_slide(slide_pos / maxf(_travel, 0.0001))
		viewmodel.weapon.set_trigger(trigger_visual)

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
	reload_total = RELOAD_EMPTY_TOTAL if reload_empty else RELOAD_TOTAL
	reload_slide_released = false
	reload_mag_seated = false
	reload_pose_blend = 0.0
	_mag_grab_done = false
	_mag_handoff_done = false
	aim = false
	trigger_held = false
	viewmodel.play_reload(reload_empty)
	_emit_ammo()
	return true


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
	Ballistics.fire(origin, dir, BALA_VELOCIDAD, BALA_TRAZADORA)
	fx.fire(origin, cam_fwd)
	emit_signal("shot_fired")
	_emit_ammo()


func _update_slide(delta: float) -> void:
	if slide_locked:
		slide_pos = _travel
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
			if slide_pos > _travel:
				slide_pos = _travel
				slide_vel = -slide_vel * SLIDE_RESTITUTION
				_emit_slide_rear_event()
			if not slide_extracted and slide_pos > _travel * SLIDE_EJECT_AT:
				slide_extracted = true
				_spawn_shell()
			if slide_pos > _travel * SLIDE_OPEN_AT:
				slide_open = true
			if slide_open and not slide_battery_emitted and slide_pos <= _travel * SLIDE_BATTERY_AT and slide_vel <= 0.0:
				slide_battery_emitted = true
				GameAudio.play_2d("slide_battery", 0.0, randf_range(0.97, 1.03))
			if slide_open and slide_pos <= _travel * SLIDE_CLOSED_AT and chamber <= 0 and mag > 0:
				slide_open = false
				mag -= 1
				chamber = 1
				_emit_ammo()
	if slide_pos > _travel * 0.87 and mag <= 0 and chamber <= 0 and not reloading:
		slide_locked = true
		slide_pos = _travel
		slide_vel = 0.0
		_emit_slide_rear_event()


func _emit_slide_rear_event() -> void:
	if slide_rear_sound_emitted:
		return
	slide_rear_sound_emitted = true
	GameAudio.play_2d("slide_rear", 0.0, randf_range(0.98, 1.06))


## RECARGA. La mano izquierda del clip sale con el cargador vacio y vuelve con
## el lleno; los dos instantes en que eso pasa son `RELOAD_*_MAG_*_T`. La pose
## del arma sigue al cargador: sube cuando se lo llevan y baja cuando vuelve.
func _update_reload(delta: float) -> void:
	if not reloading:
		return
	reload_elapsed += delta

	# El cargador cambia de mano en los dos tiempos del clip.
	if not _mag_grab_done and reload_elapsed >= _mag_out_t():
		_mag_grab_done = true
		viewmodel.magazine_to_hand()
		GameAudio.play_2d("magout", 1.0, randf_range(0.96, 1.03))
	if not _mag_handoff_done and reload_elapsed >= _mag_in_t():
		_mag_handoff_done = true
		viewmodel.magazine_to_weapon()
		_seat_reload_mag()
		recoil.kick_mag_seat()
		GameAudio.play_2d("magin", 1.0, randf_range(0.96, 1.03))

	# Recarga en seco: la mano suelta la corredera.
	if reload_empty and not reload_slide_released and reload_elapsed >= RELOAD_SLIDE_T:
		reload_slide_released = true
		slide_locked = false
		slide_pos = _travel
		slide_vel = -4.2
		slide_battery_emitted = false
		GameAudio.play_2d("slide_hand", 0.0, randf_range(0.98, 1.04))

	var mag_in_t := _mag_in_t()
	var up_t := clampf((reload_elapsed - (_mag_out_t() + 0.10)) / 0.52, 0.0, 1.0)
	var down_t := clampf((reload_elapsed - (mag_in_t + 0.06)) / 0.42, 0.0, 1.0)
	reload_pose_blend = _smooth(up_t) * (1.0 - _smooth(down_t))
	if reload_elapsed >= reload_total:
		_finish_reload()


func _mag_out_t() -> float:
	return RELOAD_EMPTY_MAG_OUT_T if reload_empty else RELOAD_MAG_OUT_T


func _mag_in_t() -> float:
	return RELOAD_EMPTY_MAG_IN_T if reload_empty else RELOAD_MAG_IN_T


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
	# El cargador vuelve al arma pase lo que pase, y la mano suelta.
	viewmodel.magazine_to_weapon()
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
