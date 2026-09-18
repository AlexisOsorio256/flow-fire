extends Node3D

signal shot_fired
signal ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool)

## AUTORIDAD MECANICA del arma: el estado fisico de la pistola.
##
## Aqui viven municion, recamara, gatillo, cadencia, corredera, recarga e
## inspeccion, y los eventos fisicos (disparo, extraccion, asiento del cargador,
## agarre del cargador). Nada mas.
##
## La presentacion esta fuera y NO tiene copia de este estado:
##   scripts/GlockViewmodel.gd  la pistola montada, la pose y la camara
##   scripts/GlockWeapon.gd     las PIEZAS del arma (corredera, gatillo, cargador)
##   scripts/GlockRecoil.gd     retroceso y peso
##   scripts/WeaponFX.gd        fogonazo, luz de boca y humo
## Glock los compone y les PASA el estado ya decidido; ellos lo representan.
##
## EL ARMA NO ESTA EN NINGUN ESQUELETO. Es un arbol de piezas (GlockWeapon), asi
## que mover la corredera o el cargador es escribir un transform, no una pose de
## hueso, y la recarga es una linea de tiempo de la MECANICA (segundos reales de
## esta pistola), no instantes remedidos de un clip de brazos ajenos.

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
## 9x19 de la Glock 19: punta de 115 granos a ~372 m/s. El proyectil no deja
## estela: una Glock normal no dispara trazadoras.
const BALA_VELOCIDAD := 372.0

## LINEA DE TIEMPO DE LA RECARGA (segundos reales, no instantes de un clip).
## El cargador sale, cae fuera de cuadro, entra el lleno y asienta. `_MAG_IN`
## marca cuando el cargador empieza a subir; `_MAG_SEAT` cuando asienta.
const RELOAD_TOTAL := 2.30
const RELOAD_EMPTY_TOTAL := 2.55
const RELOAD_MAG_OUT_T := 0.30    # el cargador empieza a salir del brocal
const RELOAD_MAG_EMPTY_T := 0.58  # ya salio del todo (y se oculta)
const RELOAD_MAG_IN_T := 1.10     # el cargador lleno empieza a entrar
const RELOAD_MAG_SEAT_T := 1.45   # asienta en el brocal (clack)
## El clack de `magin.wav` cae ~60 ms dentro de la muestra: el sonido se dispara
## ese pelo antes del asiento para que el golpe coincida con el contacto.
const MAGIN_SOUND_LEAD := 0.06
const RELOAD_SLIDE_T := 1.90      # recarga en seco: se suelta la corredera

## INSPECCION: se bloquea la corredera, se ensena la recamara y se suelta.
const INSPECT_TOTAL := 2.00
const INSPECT_LOCK_T := 0.30
const INSPECT_RELEASE_T := 1.20
const INSPECT_POSE := 0.55

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
var mag_offset := 0.0

var inspecting := false
var inspect_elapsed := 0.0
var inspect_locked := false
var inspect_released := false
var inspect_pose_blend := 0.0

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

# --- Cargador: hitos de la recarga, no cronometros sueltos -----------------
var _mag_left := false
var _mag_seated := false
var _magin_sounded := false


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
	if camera != null and viewmodel.weapon != null and not viewmodel.ads_solved:
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
	var pose := clampf(reload_pose_blend + inspect_pose_blend, 0.0, 1.0)
	viewmodel.set_pose_inputs(aim_blend, sprint_blend, player_speed, look_delta, _last_local_move, pose)
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
	mag_offset = 0.0
	_mag_left = false
	_mag_seated = false
	_magin_sounded = false
	aim = false
	trigger_held = false
	viewmodel.set_magazine_visible(true)
	_emit_ammo()
	return true


func _can_fire() -> bool:
	return not reloading and not inspecting and chamber > 0 and absf(slide_pos) < 0.0025


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

	var origin := viewmodel.muzzle.global_position
	var cam_fwd := -camera.global_transform.basis.z.normalized()
	var aim_point := camera.global_position + cam_fwd * 46.0
	var dir := (aim_point - origin).normalized()
	var right := camera.global_transform.basis.x.normalized()
	var up := camera.global_transform.basis.y.normalized()
	var move_amount := clampf(player_speed / 4.35, 0.0, 1.0)
	var spread := 0.00055 if aim_blend > 0.55 else 0.0036 + move_amount * 0.0052
	dir = (dir + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()
	Ballistics.fire(origin, dir, BALA_VELOCIDAD)
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


## RECARGA. El cargador sale del brocal, cae fuera de cuadro y entra el lleno.
## La linea de tiempo es de la mecanica (constantes de arriba), no de un clip.
## El arma sube mientras el cargador esta fuera y baja cuando asienta.
func _update_reload(delta: float) -> void:
	if not reloading:
		return
	reload_elapsed += delta

	# 1. El cargador empieza a salir.
	if not _mag_left and reload_elapsed >= RELOAD_MAG_OUT_T:
		_mag_left = true
		GameAudio.play_2d("magout", 1.0, randf_range(0.96, 1.03))
	# 2. Ya salio del todo: se oculta hasta que entre el lleno.
	if reload_elapsed >= RELOAD_MAG_EMPTY_T and reload_elapsed < RELOAD_MAG_IN_T:
		viewmodel.set_magazine_visible(false)
	# 3. Entra el cargador lleno.
	if reload_elapsed >= RELOAD_MAG_IN_T and reload_elapsed < RELOAD_MAG_SEAT_T:
		viewmodel.set_magazine_visible(true)
	# 4. El clack de la muestra cae ~60 ms dentro: se adelanta el aviso.
	if not _magin_sounded and reload_elapsed >= RELOAD_MAG_SEAT_T - MAGIN_SOUND_LEAD:
		_magin_sounded = true
		GameAudio.play_2d("magin", 1.0, randf_range(0.96, 1.03))
	# 5. Asiento: municion + golpe de masa.
	if not _mag_seated and reload_elapsed >= RELOAD_MAG_SEAT_T:
		_mag_seated = true
		_seat_reload_mag()
		recoil.kick_mag_seat()

	# Recarga en seco: se suelta la corredera.
	if reload_empty and not reload_slide_released and reload_elapsed >= RELOAD_SLIDE_T:
		reload_slide_released = true
		slide_locked = false
		slide_pos = _travel
		slide_vel = -4.2
		slide_battery_emitted = false
		GameAudio.play_2d("slide_hand", 0.0, randf_range(0.98, 1.04))

	# El cargador se mueve con la mecanica, no con una animacion importada.
	mag_offset = _mag_offset_at(reload_elapsed)
	viewmodel.set_magazine_offset(mag_offset)

	var up_t := clampf((reload_elapsed - (RELOAD_MAG_OUT_T + 0.05)) / 0.35, 0.0, 1.0)
	var down_t := clampf((reload_elapsed - (RELOAD_MAG_SEAT_T + 0.05)) / 0.35, 0.0, 1.0)
	reload_pose_blend = _smooth(up_t) * (1.0 - _smooth(down_t))
	if reload_elapsed >= reload_total:
		_finish_reload()


## Avance del cargador: 0 asentado, 1 fuera del todo. En el hueco en que esta
## fuera no se dibuja (el nodo es el mismo cargador saliendo y entrando).
func _mag_offset_at(t: float) -> float:
	if t < RELOAD_MAG_OUT_T:
		return 0.0
	if t < RELOAD_MAG_EMPTY_T:
		return _smooth((t - RELOAD_MAG_OUT_T) / (RELOAD_MAG_EMPTY_T - RELOAD_MAG_OUT_T))
	if t < RELOAD_MAG_IN_T:
		return 1.0
	if t < RELOAD_MAG_SEAT_T:
		return 1.0 - _smooth((t - RELOAD_MAG_IN_T) / (RELOAD_MAG_SEAT_T - RELOAD_MAG_IN_T))
	return 0.0


## INSPECCION. Bloquea la corredera, ensena la recamara y la suelta. Es la
## mecanica de la pistola sola; no hay brazos que la abracen.
func inspect_weapon() -> void:
	if reloading or inspecting:
		return
	inspecting = true
	inspect_elapsed = 0.0
	inspect_locked = false
	inspect_released = false
	GameAudio.play_2d("handling", 6.0, randf_range(0.98, 1.02))


func _update_inspect(delta: float) -> void:
	if not inspecting:
		inspect_pose_blend = 0.0
		return
	inspect_elapsed += delta
	if not inspect_locked and inspect_elapsed >= INSPECT_LOCK_T:
		inspect_locked = true
		slide_locked = true
		slide_pos = _travel
		slide_vel = 0.0
		GameAudio.play_2d("slide_hand", 5.0, randf_range(0.99, 1.03))
	if not inspect_released and inspect_elapsed >= INSPECT_RELEASE_T:
		inspect_released = true
		slide_locked = false
		slide_pos = _travel
		slide_vel = -4.2
		slide_battery_emitted = false
	var t := clampf(inspect_elapsed / INSPECT_TOTAL, 0.0, 1.0)
	inspect_pose_blend = INSPECT_POSE * _smooth(minf(1.0, t * 4.0)) * (1.0 - _smooth(clampf((t - 0.55) / 0.45, 0.0, 1.0)))
	if inspect_elapsed >= INSPECT_TOTAL:
		inspecting = false
		inspect_pose_blend = 0.0


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
	mag_offset = 0.0
	viewmodel.set_magazine_offset(0.0)
	viewmodel.set_magazine_visible(true)
	_emit_ammo()


func _spawn_shell() -> void:
	if not is_instance_valid(get_tree().current_scene):
		return
	Shell.spawn(get_tree().current_scene, viewmodel.ejection_port.global_transform, slide_vel, player_velocity)


func _emit_ammo() -> void:
	ammo_changed.emit(mag, chamber, reserve, reloading)


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
