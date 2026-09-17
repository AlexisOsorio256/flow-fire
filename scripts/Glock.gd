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
##
## Reparto de responsabilidades, en orden de lectura:
##   1. constantes de mecanica (recorrido de corredera, instantes de recarga)
##   2. estado mecanico
##   3. API publica (gatillo, recarga, inspeccion, senales)
##   4. ciclo por frame y eventos fisicos
##   5. casquillo (cuerpo fisico real; su malla es procedural)
const MAG_SIZE := 17
# Ciclo mecánico de la corredera. El recorrido de 39 mm es el real de una
# Glock 19 y está confirmado con la geometría del arma.
#
# Sobre el TIEMPO: no existe una medición pública verificable del ciclo completo
# de una Glock 19 que se haya podido citar aquí, así que el valor no se presenta
# como dato de ese modelo. Lo que sí está documentado en captura de alta
# velocidad (50 924 fps, Sight Picture Media) es que la corredera EMPIEZA a
# moverse en el momento del ignicionado y que puede recorrer 2-3 mm antes de que
# el proyectil salga del cañón; eso justifica que el impulso se aplique en
# _fire() y no después. El ciclo que sale de esta pareja k/c es de ~59 ms
# medidos con --geometrydebug (SLIDECYCLE): dentro del rango de una pistola de
# servicio 9 mm y validado a ojo en cámara lenta. Es un valor CALIBRADO, no una
# medición de Glock 19.
const SLIDE_TRAVEL := 0.039
const SLIDE_K := 4000.0        # rigidez equivalente del muelle recuperador
const SLIDE_C := 80.0          # amortiguación (zeta 0.632)
const SLIDE_IMPULSE := 5.90    # impulso CALIBRADO para tocar el tope trasero
# (con 5.45 el pico medido en juego era 38.8 mm y la corredera NO llegaba al
# tope: el evento trasero solo sonaba al bloquear en vacio y el disparo normal
# no tenia mecanica audible; con 5.90 el tope llega a ~12 ms y la bateria a
# ~54 ms (SLIDECYCLE con subpaso de 1 ms: pico 39+ mm; en juego el subpaso de
# 2.5 ms amortigua mas y el margen es justo pero suficiente, verificado en
# --slowmo: la corredera toca 37+ mm entre frames y los eventos suenan)
const SLIDE_RESTITUTION := 0.25  # rebote contra el tope trasero
const SLIDE_EJECT_AT := 0.030  # el casquillo sale con el puerto ya abierto (~8 ms)
# Instantes de la recarga, MEDIDOS sobre las claves de Reload (3.125 s) y
# Reload_Empty (3.917 s) del rig NUEVO (recorrido del hueso Magazine_924):
#
#   tactica: el cargador ya se mueve a 0.25 s (44 mm) y esta fuera del todo a
#     ~1.17 s (189 mm); el nuevo entra sobre 1.25-1.50 s y asienta a ~2.50 s
#     (9.5 mm, en casa a 3.0 s).
#   vacia: igual hasta 2.25 s; el cargador nuevo asienta sobre 3.50 s.
#     La corredera va clavada ATRAS todo el gesto (26.3 mm) y se libera a
#     2.79-3.00 s (en casa a 3.0 s).
const RELOAD_MAG_OUT_T := 0.30
const RELOAD_MAG_IN_T := 2.50
const RELOAD_SLIDE_T := 2.90
const RELOAD_EMPTY_TOTAL := 4.00    # Reload_Empty (3.917) + mezcla al idle
const RELOAD_TACTICAL_TOTAL := 3.20  # Reload (3.125) + mezcla al idle

# --- Estado mecanico -------------------------------------------------------
var camera: Camera3D  # solo para la direccion del disparo
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
var slide_open := false  # la corredera llego a abrirse (para recamarar al cerrar)
var slide_rear_sound_emitted := true
var slide_battery_emitted := true
# Posicion visual del gatillo (0..1), derivada de trigger_held. La consume el
# viewmodel en apply_mechanics: es presentacion, pero la decide el estado del
# gatillo, que es mecanico.
var trigger_visual := 0.0

var reloading := false
var reload_elapsed := 0.0
var reload_total := 0.0
var reload_empty := false
var reload_slide_released := false
var reload_mag_seated := false
var mag_sound_out := false
var reload_pose_blend := 0.0  # 0..1: lo consume la pose de recarga del viewmodel

# --- Entradas de gameplay --------------------------------------------------
var aim := false
var sprinting := false
var aim_blend := 0.0  # apuntado suavizado: lo leen Player, HUD y el post
var sprint_blend := 0.0
var player_speed := 0.0
var look_delta := Vector2.ZERO
var player_velocity := Vector3.ZERO
var _last_local_move := Vector2.ZERO

var last_delta := 0.0  # lo lee --recoilprobe

# Pulso del disparo para la exposicion del bodycam (lo lee HUD.gd).
var shot_pulse := 0.0


func _ready() -> void:
	recoil = GlockRecoil.new()
	viewmodel = GlockViewmodel.new()
	viewmodel.name = "Viewmodel"
	viewmodel.recoil = recoil
	add_child(viewmodel)
	viewmodel.mount()
	# El fogonazo cuelga de la boca real del rig (ver scripts/WeaponFX.gd).
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


## Apuntado suavizado. Vive aqui (no en la pose) porque es estado de input
## compartido: lo consumen la pose, la camara de Player, el post del HUD y
## el laboratorio de diagnostico.
func _update_aim(delta: float) -> void:
	var target_sprint := 1.0 if sprinting else 0.0
	sprint_blend += (target_sprint - sprint_blend) * (1.0 - exp(-5.5 * delta))
	var target_aim := (1.0 if aim else 0.0) * (1.0 - sprint_blend)
	aim_blend += (target_aim - aim_blend) * (1.0 - exp(-9.0 * delta))


func _process(delta: float) -> void:
	last_delta = delta
	_update_aim(delta)
	_update_trigger(delta)
	_update_slide(delta)
	_update_reload(delta)
	recoil.update(delta)
	viewmodel.set_pose_inputs(aim_blend, sprint_blend, player_speed, look_delta, _last_local_move, reload_pose_blend)
	viewmodel.update(delta)
	viewmodel.apply_mechanics(slide_pos, SLIDE_TRAVEL, trigger_visual)

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
	reload_elapsed = 0.0
	# Recarga en vacío = no hay cartucho en recámara: hay que soltar la
	# corredera para alimentarlo. Antes exigía además slide_locked, así que una
	# recarga con la recámara vacía y la corredera en batería dejaba el arma
	# cargada pero sin cartucho listo (mag=17, chamber=0).
	reload_empty = chamber <= 0
	# La animacion la reproduce el viewmodel, una sola vez por recarga. Cada
	# estado mecanico tiene su clip: `Reload` no contiene ningun gesto de
	# corredera, asi que la recarga tactica no tiene que cortar nada para no
	# ensenar algo que la mecanica no hace.
	reload_total = RELOAD_EMPTY_TOTAL if reload_empty else RELOAD_TACTICAL_TOTAL
	reload_slide_released = false
	reload_mag_seated = false
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

	# Gatillo en seco: con la recámara vacía y la corredera en batería la aguja
	# golpea en vacío. Antes no sonaba nada y el arma parecía muerta.
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
		else:
			trigger_ready = true


func _fire() -> void:
	chamber -= 1
	trigger_ready = false
	trigger_latched = true
	trigger_reset_timer = 0.075
	slide_extracted = false
	slide_open = false
	slide_rear_sound_emitted = false
	slide_battery_emitted = false
	slide_vel += SLIDE_IMPULSE
	shot_pulse = 1.0

	# Evento fisico del disparo: el retroceso del arma y de los brazos lo integra
	# GlockRecoil (tres escalas de tiempo, ver su cabecera). Aqui solo se avisa.
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
		# Se integra por subpasos en vez de usar Springs porque los avisos
		# ("abrió", "volvió a batería", "tocó extraer") hay que verlos DENTRO del
		# recorrido: a pocos FPS el ciclo entero de la corredera cabe en un frame
		# y mirando solo el estado final no se recamarraba ni salía el casquillo.
		# El subpaso de 2.5 ms es estable para k=2560 y c=70.8.
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
				# Tope trasero real: la corredera golpea el armazón y rebota.
				slide_pos = SLIDE_TRAVEL
				slide_vel = -slide_vel * SLIDE_RESTITUTION
				_emit_slide_rear_event()

			if not slide_extracted and slide_pos > SLIDE_EJECT_AT:
				slide_extracted = true
				_spawn_shell()

			# Alimentar el siguiente cartucho cuando la corredera vuelve a
			# batería. Se detecta por evento (abrió y volvió a cerrar) y no por
			# velocidad: la velocidad oscila alrededor de cero al asentarse.
			if slide_pos > 0.02:
				slide_open = true
			# Cierre contra la bateria: la corredera vuelve a casa (~54 ms) y el
			# metal golpea metal. Es el segundo transitorio real del disparo
			# (el primero es el tope trasero a ~13 ms); suena a peso, no a otro
			# disparo, porque va 4 dB por debajo del trasero y grave (pitch 0.7).
			if slide_open and not slide_battery_emitted and slide_pos <= 0.004 and slide_vel <= 0.0:
				slide_battery_emitted = true
				# Transitorio de bateria (golpe sordo, 75% de energia <800 Hz).
				# Otra grabacion distinta de la del tope trasero: es el segundo
				# evento fisico del ciclo, no el primero repetido.
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
	# Tope trasero: chasquido de acero (85% de energia >2,5 kHz) a ~12 ms del
	# estampido. Nivel base de la tabla; el de bateria va 4 dB por debajo.
	GameAudio.play_2d("slide_rear", 0.0, randf_range(0.98, 1.06))


func _update_reload(delta: float) -> void:
	if not reloading:
		return
	reload_elapsed += delta

	# El sonido va en el instante en que ocurre el gesto, no al empezar.
	if not mag_sound_out and reload_elapsed >= RELOAD_MAG_OUT_T:
		mag_sound_out = true
		GameAudio.play_2d("magout", 0.0, randf_range(0.95, 1.05))

	if not reload_mag_seated and reload_elapsed >= RELOAD_MAG_IN_T:
		_seat_reload_mag()
		# El cargador deja de ser una cifra abstracta en el mismo instante en
		# que su base golpea el brocal: el gesto del rig ya lo lleva hasta ahí,
		# y este rebote breve transmite la reacción de esa masa a la muñeca.
		# Es deliberadamente una fracción del retroceso de un disparo (~1 mm /
		# ~0,2° de pico, no otro latigazo) y reutiliza el resorte físico existente.
		recoil.kick_mag_seat()
		GameAudio.play_2d("magin", 0.0, randf_range(0.95, 1.05))

	# Corredera: en una recarga en vacío se libera a mano en el mismo momento en
	# que la animación del autor la suelta.
	if reload_empty and not reload_slide_released and reload_elapsed >= RELOAD_SLIDE_T:
		reload_slide_released = true
		slide_locked = false
		slide_pos = SLIDE_TRAVEL
		slide_vel = -4.2
		# La corredera volviendo a bateria: mismo evento fisico que el cierre
		# del disparo, asi que usa su misma muestra.
		GameAudio.play_2d("slide_battery", 1.0)

	# La pose sube con la mano (0.05-0.30 s), se mantiene mientras está el
	# cargador fuera y baja cuando ya está dentro.
	var up_t := clampf((reload_elapsed - 0.05) / 0.25, 0.0, 1.0)
	var down_t := clampf((reload_elapsed - RELOAD_MAG_IN_T) / 0.35, 0.0, 1.0)
	reload_pose_blend = _smooth(up_t) * (1.0 - _smooth(down_t))

	if reload_elapsed >= reload_total:
		_finish_reload()


## Inspeccionar el arma (tecla F). La animacion existe en el rig de brazos, asi
## que no hay coreografia que inventar: se reproduce y el AnimationPlayer vuelve
## solo al idle al terminar (queue en el propio clip).
func inspect_weapon() -> void:
	if reloading:
		return
	viewmodel.play_anim("Inspect")


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
	viewmodel.blend_to_idle(0.14)
	_emit_ammo()


func _spawn_shell() -> void:
	if not is_instance_valid(get_tree().current_scene):
		return
	var shell = preload("res://scripts/Shell.gd").new()
	shell.mass = 0.008
	shell.collision_layer = 2
	shell.collision_mask = 1
	shell.continuous_cd = true

	# Vaina procedural: el asset no trae cartucho suelto aprovechable (sus
	# balas van soldadas al cargador en la malla), asi que el casquillo se
	# construye aqui y no depende de ningun arma concreta.
	var casing_pivot := Node3D.new()
	casing_pivot.name = "Casing"
	# 9x19 real = 19,15 mm de largo x 4,9 mm de radio de culote.
	var casing_mesh := CylinderMesh.new()
	casing_mesh.top_radius = 0.0049
	casing_mesh.bottom_radius = 0.0049
	casing_mesh.height = 0.01915
	casing_mesh.radial_segments = 12
	casing_mesh.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.53, 0.18)
	brass.metallic = 0.95
	brass.roughness = 0.28
	casing_mesh.material = brass
	var casing_inst := MeshInstance3D.new()
	casing_inst.name = "CasingMesh"
	casing_inst.mesh = casing_mesh
	casing_inst.rotation.x = deg_to_rad(90.0)
	casing_pivot.add_child(casing_inst)
	shell.add_child(casing_pivot)
	const CASING_LEN := 0.01915
	const CASING_RAD := 0.0049

	# La colisión no necesita seguir la malla: un cilindro del tamaño medido de
	# la vaina es más barato y más estable que un convex hull de 432 vértices.
	var shape := CylinderShape3D.new()
	shape.height = CASING_LEN
	shape.radius = CASING_RAD
	var collider := CollisionShape3D.new()
	collider.shape = shape
	# El cilindro nace con el eje en Y y la vaina va tumbada a lo largo del
	# cañón, que en el marco del arma es Z.
	collider.rotation.x = deg_to_rad(-90.0)
	shell.add_child(collider)

	var physics_mat := PhysicsMaterial.new()
	physics_mat.bounce = 0.52
	physics_mat.friction = 0.45
	shell.physics_material_override = physics_mat
	# Rozamiento del aire sobre una vaina de 8 g: frena en vuelo en vez de
	# cruzar la pantalla de lado a lado en 90 ms (que es lo que hacía).
	shell.linear_damp = 0.9
	shell.angular_damp = 0.5

	get_tree().current_scene.add_child(shell)
	# Grupo de medición: la herramienta de captura en cámara lenta sigue a los
	# casquillos para comprobar que se ven salir (igual que "targets").
	shell.add_to_group("shells")
	shell.global_transform = viewmodel.ejection_port.global_transform
	var basis := viewmodel.ejection_port.global_transform.basis
	# El puerto está en la cara derecha del arma: el casquillo sale a la derecha
	# (+X), arriba (+Y) y algo hacia atrás (+Z, que es la cola del arma).
	# La vaina sale empujada por el extractor: hacia atrás hereda parte de la
	# velocidad real de la corredera, y el expulsor la tira a la derecha y
	# arriba. El giro es rápido (una vaina recién expulsada voltea).
	var local_vel := Vector3(1.5 + randf() * 0.7, 1.3 + randf() * 0.6, maxf(0.6, slide_vel * 0.35))
	shell.linear_velocity = basis * local_vel + player_velocity * 0.8
	shell.angular_velocity = Vector3(randf_range(-34.0, 34.0), randf_range(-34.0, 34.0), randf_range(-34.0, 34.0))


func _emit_ammo() -> void:
	ammo_changed.emit(mag, chamber, reserve, reloading)


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
