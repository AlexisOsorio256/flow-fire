extends Node3D

signal shot_fired
signal ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool)

## Viewmodel de FlowFire: UNA pistola con SUS manos en UN solo rig.
##
## Asset: `assets/models/full9mm_2k.glb` ("9mm Pistol | First Person Animations"
## de 1Matzh). Trae brazos + pistola ya agarrada y animada en un solo esqueleto,
## asi que NO hay segunda arma, ni fallback, ni rig legacy: lo que se ve es lo
## que hay.
##
## Cadena en runtime:
##   Camera -> WeaponRig -> Glock(logica) -> PoseRoot -> WristPivot -> RecoilNode
##     -> ArmsMount -> ArmsRoot(instancia del GLB) -> Skeleton3D (+piel)
##     -> SlideAttach -> Muzzle -> WeaponFX (fogonazo)
##
## Autoridades: la LOGICA (municion, corredera, gatillo, cadencia, recarga) manda
## el estado mecanico; las ANIMACIONES del asset mandan la pose HUMANA (manos,
## munecas, brazos) y arrastran el arma entera (hueso Weapon_922); la corredera
## (Slidder_919) y el gatillo (Weapon_Trigger_921) los escribe la logica cada
## frame SOBRE el esqueleto (sus pistas de animacion se eliminan al cargar, ver
## _strip_mechanical_tracks), asi que mecanica logica y mecanica visible son la
## misma realidad. El cargador lo lleva la mano en la animacion de recarga y la
## logica solo cuenta cartuchos en los instantes medidos. La MIRA visible (alza
## real de la corredera, leida por BoneAttachment del hueso Slidder) define el ADS.
##
## Reparto de este archivo: **mecanica + montaje del rig**. La presentacion del
## fogonazo (malla, luz de boca y humo) vive en `scripts/WeaponFX.gd` y se le
## entrega ya colgada de la boca real; aqui solo se la avisa con `fx.fire()`.
const MAG_SIZE := 17
const GUN_LENGTH := 0.186  # Glock 19 real: 186 mm de punta a punta.
# Ojo -> mira trasera en ADS. Estaba en 0.42 m y era la causa del encuadre: con
# el arma tan cerca, los antebrazos del rig caen en el borde inferior y ocupan
# media pantalla. Medido con la metrica SILUETA de --armdiag (viewport 16:9):
#
#   0.42 m -> brazos 41.2% del encuadre, bandas laterales inferiores 70.9%
#   0.48 m -> brazos 34.8%, bandas 57.2%
#   0.52 m -> brazos 30.9%, bandas 45.5%
#   0.54 m -> brazos 28.7%, bandas 36.3%   <- elegido
#   0.56 m -> brazos 26.5%, bandas 29.2%
#   0.62 m -> brazos 20.4%, bandas 13.9%
#
# No es un offset de encuadre: es la distancia a la que un tirador real tiene el
# alza del ojo, y la unica palanca que queda sin tocar la escala de los brazos
# (atada a la empunadura del asset) ni la pose del autor. El porcentaje del
# ARMA baja en la misma proporcion (0.9% -> 0.4%) porque mira al frente y se ve
# de canto, no porque el arma se aleje del centro. Se para en 0.54 y no en 0.62
# porque a partir de ahi el alza trasera deja de leerse.
const ADS_SIGHT_DISTANCE := 0.54
# Pose de cadera (lista): el arma va baja pero visible. Lleva plegado el
# encuadre validado: antes eran HIP_POS=(0, 0.062, 0) mas un desplazamiento fijo
# de (0, 0.06, -0.34) aplicado despues de la pose; al resolver el ADS de verdad
# ese desplazamiento rompia la solucion, asi que ahora vive aqui y la pose de
# ADS sale SOLO del solver (_solve_ads).
const HIP_POS := Vector3(0.0, 0.122, -0.34)  # incluye el encuadre de cadera validado
const GUN_TOP_OVER_ORIGIN := 0.035  # La corredera queda 3.5 cm sobre el origen.
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
# Impulso de cabeceo del ARMA en el disparo (rad/s). Es la unica fuente del
# latigazo visible desde que el clip Fire no mueve el hueso del arma: MEDIDO con
# --firecurve, la animacion daba 0.24 grados en los primeros 40 ms y subia en
# rampa hasta 180 ms, que es lo que hacia que la vaina pareciese moverse mas que
# la pistola. Con 4.2 rad/s la boca sube ~8 grados con pico a ~50 ms.
const MAIN_RECOIL_KICK := 4.2
# Recorrido VISUAL de la corredera en el asset: la animacion Fire mueve el
# hueso Slidder 33.6 mm (MEDIDO EN ESTE ASSET, pico a 0.167 s). La logica sigue
# en metros reales (39 mm de G19) y aqui se mapea linealmente, asi que la
# corredera visible reproduce el estado logico sin copiar la pista animada.
const SLIDE_VISUAL_TRAVEL := 0.0336
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
# Pose de recarga: el tirador sube el arma y la gira para ver el brocal del
# cargador (es lo que hace de verdad). Sin esto la empuñadura queda por debajo
# del borde de la pantalla y el cargador sale del encuadre sin verse nunca.
const RELOAD_POSE_UP := 0.075     # sube el arma
const RELOAD_POSE_FWD := 0.045    # y la acerca algo a la cámara
const RELOAD_POSE_PITCH := 0.17   # gira el brocal hacia la cara
const RELOAD_POSE_ROLL := -0.30
# Geometria del arma, MEDIDA EN ESTE ASSET (offsets en espacio local del hueso
# que la mueve; extraccion documentada en --gundiag):
#  - corredera (hueso Slidder_919): caja 29.4 x 42.4 x 176.3 mm; alza trasera y
#    punto delantero centroides de su geometria superior; linea de mira
#    (0, -0.004, 1.0), radio 158.3 mm, 13.6 mm sobre la boca (una G19 real anda
#    por 160 mm y ~13 mm).
#  - boca 2.7 mm por delante del frente de corredera; puerto lado derecho.
#  - gatillo (hueso Weapon_Trigger_921): la animacion Fire lo lleva 4.6 mm
#    hacia atras con pico a 0.083 s; esa es la direccion que usa la logica.
const SLIDE_BONE := "Slidder_919"
const BARREL_BONE := "Barrel_920"
const WEAPON_BONE := "Weapon_922"
const TRIGGER_BONE := "Weapon_Trigger_921"
const MAG_BONE := "Magazine_924"
const SIGHT_REAR_SLIDE := Vector3(-0.0037, 0.01081, -0.0538)
const SIGHT_FRONT_SLIDE := Vector3(-0.0037, 0.01022, 0.10447)
const MUZZLE_SLIDE := Vector3(-0.0037, -0.00283, 0.11336)
const EJECT_SLIDE := Vector3(0.00922, 0.00478, 0.00863)
const TRIGGER_PULL := Vector3(0.000153, -0.000112, -0.004601)
# Caja de la corredera en su espacio (para encuadre y diagnostico).
const SLIDE_BOX := AABB(Vector3(-0.0184, -0.0279, -0.0656), Vector3(0.0294, 0.0424, 0.1763))

var camera: Camera3D
var pose_root: Node3D
var recoil_node: Node3D
var muzzle: Node3D
var ejection_port: Node3D
var fx: WeaponFX  # presentación del fogonazo (ver scripts/WeaponFX.gd)
var viewmodel_light: OmniLight3D

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
var slide_open := false  # la corredera llegó a abrirse (para recamarar al cerrar)
var slide_rear_sound_emitted := true
var slide_battery_emitted := true
var reload_pose_blend := 0.0

# Retroceso en capas independientes, cada una con su escala de tiempo:
#  1) mecánica: corredera/gatillo/cargador (la manda la lógica, ~60 ms)
#  2) arma en la mano: recoil_node girando sobre la MUÑECA (~240 ms)
#  3) brazos/viewmodel: pose_root entero, más lento y blando (~660 ms)
#  4) cámara: resortes de Player.gd, la más lenta
# No son el mismo movimiento disfrazado: cada capa tiene constante y amplitud
# propias, y se miden por separado en --recoilprobe.
var wrist_pivot := Node3D.new()
var recoil_pos := Vector3.ZERO
var recoil_vel := Vector3.ZERO
var recoil_rot := Vector3.ZERO
var recoil_rot_vel := Vector3.ZERO
var arm_recoil_pos := Vector3.ZERO
var arm_recoil_vel := Vector3.ZERO
var arm_recoil_rot := Vector3.ZERO
var arm_recoil_rot_vel := Vector3.ZERO
var wrist_local := Vector3.ZERO  # punto de giro medido (frame de arma)

var aim := false
var sprinting := false
var aim_blend := 0.0
var sprint_blend := 0.0

# Pulso del disparo para la exposición del bodycam (lo lee HUD.gd). No es
# estado mecánico: es la marca de "acaba de sonar un disparo" que consume el post.
var shot_pulse := 0.0

var reloading := false
var reload_elapsed := 0.0
var reload_total := 0.0
var reload_empty := false
var reload_slide_released := false
var reload_mag_seated := false
var mag_sound_out := false

var last_delta := 0.0  # TEMPORAL: lo lee --recoilprobe
var player_speed := 0.0
var look_delta := Vector2.ZERO
var bob_phase := 0.0
var idle_phase := 0.0
var sway := Vector2.ZERO
var player_velocity := Vector3.ZERO

var sight_marker: Node3D
var front_marker: Node3D
var ads_offset := Vector3(0.0, 0.15, -0.24)  # pose de ADS: la resuelve _solve_ads()
var ads_rot := Vector3.ZERO  # giro de ADS resuelto junto al offset (radianes)
var ads_solved := false  # _solve_ads ya corrio con el arma real montada
# Caja de la corredera real en espacio del hueso (ver SLIDE_BOX): la usan el
# encuadre y el diagnostico. La escala del asset (manos ~2.5x la corredera en
# el mismo espacio y pose, medido con --gundiag) es la del autor y se conserva.
var gun_box := SLIDE_BOX
# Escala uniforme del conjunto (manos+arma, un solo rig). Valor CALIBRADO de
# FlowFire para el encuadre: el asset esta modelado ~1:1 en metros (corredera
# 29.4 mm como una real), asi que esta escala tambien agranda las manos; se
# conserva porque el encuadre y el ADS estan validados sobre ella.
var arms_scale := 1.362
var trigger_visual := 0.0
# Huesos mecanicos (autoridad de la logica) y sus reposos locales.
var slide_bone := -1
var trigger_bone := -1
var slide_rest := Vector3.ZERO
var trigger_rest := Vector3.ZERO
var slide_attach: BoneAttachment3D  # la mira/boca van con la corredera real


func _ready() -> void:
	pose_root = Node3D.new()
	pose_root.name = "PoseRoot"
	add_child(pose_root)

	wrist_pivot.name = "WristPivot"
	pose_root.add_child(wrist_pivot)
	recoil_node = Node3D.new()
	recoil_node.name = "RecoilNode"
	wrist_pivot.add_child(recoil_node)

	_build_viewmodel_light()
	_build_viewmodel()
	_install_arms()
	# El ADS se resuelve con el arma real ya montada; si la camara aun no llego
	# (la entrega setup() despues), se resuelve alli.
	if camera != null and arms_ok and not ads_solved:
		camera.force_update_transform()
		_solve_ads()
	_emit_ammo()


## Luces del viewmodel: el arma vive en un interior oscuro y con su albedo real
## (polímero ~0.08) se leía como una mancha negra: medido, 5/255 de luminancia
## media sobre los píxeles del arma. Dos luces cortas y sin sombras (clave
## arriba-izquierda y relleno desde la cámara) la definen sin tocar la escena.
## Cuelgan de pose_root para que acompañen al arma en recarga y apuntado.
func _build_viewmodel_light() -> void:
	viewmodel_light = OmniLight3D.new()
	viewmodel_light.name = "ViewmodelKey"
	viewmodel_light.light_color = Color(0.94, 0.96, 1.0)
	viewmodel_light.light_energy = 2.9
	viewmodel_light.omni_range = 1.5
	viewmodel_light.omni_attenuation = 1.35
	viewmodel_light.shadow_enabled = false
	# Detrás y arriba: la cara que ve la cámara al apuntar (el dorso de la
	# corredera y la mira) tiene que estar iluminada, o el punto de mira se lee
	# negro y no se puede apuntar con él.
	viewmodel_light.position = Vector3(-0.30, 0.26, 0.42)
	pose_root.add_child(viewmodel_light)

	var fill := OmniLight3D.new()
	fill.name = "ViewmodelFill"
	fill.light_color = Color(0.95, 0.97, 1.0)
	fill.light_energy = 0.95
	fill.omni_range = 1.3
	fill.omni_attenuation = 1.2
	fill.shadow_enabled = false
	fill.position = Vector3(0.28, -0.08, 0.46)
	pose_root.add_child(fill)


func setup(cam: Camera3D) -> void:
	camera = cam
	# La camara llega DESPUES de _ready (el arma se crea con add_child y la
	# camara se entrega luego), asi que el ADS se resuelve aqui si el arma real
	# ya esta montada. Sin esto _solve_ads no corria nunca y el ADS era un
	# offset fijo a mano: esa fue la causa del aimtest en rojo.
	if arms_ok and not ads_solved:
		_solve_ads()


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
	# Recarga en vacío = no hay cartucho en recámara: hay que soltar la
	# corredera para alimentarlo. Antes exigía además slide_locked, así que una
	# recarga con la recámara vacía y la corredera en batería dejaba el arma
	# cargada pero sin cartucho listo (mag=17, chamber=0).
	reload_empty = chamber <= 0
	# La animación del autor se reproduce a velocidad 1 (es su cadencia, y con
	# ella las claves caen donde él las puso). Cada estado mecánico tiene ya su
	# clip: Reload_easy no contiene ningún gesto de corredera, así que la
	# recarga táctica no necesita cortar nada para no enseñar algo que la
	# mecánica no hace.
	reload_total = RELOAD_EMPTY_TOTAL if reload_empty else RELOAD_TACTICAL_TOTAL
	reload_slide_released = false
	reload_mag_seated = false
	aim = false
	trigger_held = false
	# `_play_reload_animation()` resuelve una sola vez la animación que
	# corresponde al estado mecánico. Antes se llamaba también a
	# `_play_arms_anim()` en el mismo frame y el clip se reiniciaba dos veces.
	_play_reload_animation()
	_emit_ammo()
	return true


## Arranca la animación de recarga del autor sin encolar el idle: el final lo
## decide la lógica (corte táctico o mezcla al terminar).
func _play_reload_animation() -> void:
	_play_arms_anim("Reload_Empty" if reload_empty else "Reload")


func _blend_to_idle(blend: float) -> void:
	if arms_player == null:
		return
	var idle := _resolve_arms_idle()
	if idle != "":
		arms_player.play(idle, blend)


func _can_fire() -> bool:
	return not reloading and chamber > 0 and absf(slide_pos) < 0.0025


func _process(delta: float) -> void:
	last_delta = delta
	_update_trigger(delta)
	_update_slide(delta)
	_update_recoil(delta)
	_update_reload(delta)
	_update_pose(delta)
	_apply_pistol_parts()

	shot_pulse = maxf(0.0, shot_pulse - delta * 8.0)
	if fx != null:
		fx.update(delta)


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

	# 2) EL ARMA. El clip Fire ya no mueve el hueso del arma (ver
	# _strip_mechanical_tracks): su latigazo es este, y es fisica, no amplitud
	# gratis. Tres escalas de tiempo para que se lea como masa:
	#   ~10 ms  muneca: el golpe del disparo llega antes de que la mano pueda
	#           hacer nada (pico de ~1 grado, casi un tic).
	#   ~50 ms  arma: la boca sube porque gira sobre la muneca (k=520 -> ~8
	#           grados) y vuelve controlada hacia los 250 ms. Este es el golpe
	#           que antes no existia: MEDIDO, la animacion daba 0.2 grados en
	#           los primeros 40 ms.
	#   mas      brazos y camara: absorben despues, con menos amplitud.
	# La direccion x (cabeceo) es la que sube la boca; el retroceso trasero va
	# en z, que en el marco del arma es hacia el tirador.
	recoil_vel += Vector3((randf() - 0.5) * 0.02, 0.035, 0.22 + randf() * 0.02)
	recoil_rot_vel += Vector3(MAIN_RECOIL_KICK + randf() * 0.35, (randf() - 0.5) * 0.2, (randf() - 0.5) * 0.3)
	# 3) brazos: el hombro absorbe mas lento y mas blando que la muneca.
	# Es la capa que da la sensacion de masa del brazo, no un segundo latigazo.
	arm_recoil_vel += Vector3((randf() - 0.5) * 0.03, 0.05, 0.22 + randf() * 0.03)
	arm_recoil_rot_vel += Vector3(0.8 + randf() * 0.16, 0.0, (randf() - 0.5) * 0.16)

	GameAudio.play_shot()
	_play_arms_anim("Fire")

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


func _update_recoil(delta: float) -> void:
	# Capa 2: el arma gira en la mano sobre la muñeca. El pivote va detrás y
	# debajo de la empuñadura (medido de la caja del arma), así que la boca sube
	# mientras la empuñadura casi no se mueve: es lo que hace un retroceso real y
	# lo que antes se sentía "forzado" (giro sobre el centro del arma).
	# k=520/c=18 (zeta 0.39): pico del cabeceo a ~50 ms y recuperación
	# controlada hacia 250 ms. Con el resorte anterior (k=700, zeta 0.75) el
	# arma volvía a casa en 150 ms y no llegaba a subir.
	var pos := Springs.vector(recoil_pos, recoil_vel, 520.0, 18.0, delta)
	recoil_pos = pos[0]
	recoil_vel = pos[1]
	var rot := Springs.vector(recoil_rot, recoil_rot_vel, 520.0, 18.0, delta)
	recoil_rot = rot[0]
	recoil_rot_vel = rot[1]
	recoil_pos = Vector3(clampf(recoil_pos.x, -0.04, 0.04), clampf(recoil_pos.y, -0.03, 0.03), clampf(recoil_pos.z, -0.03, 0.055))
	recoil_rot = Vector3(clampf(recoil_rot.x, -0.24, 0.24), clampf(recoil_rot.y, -0.08, 0.08), clampf(recoil_rot.z, -0.1, 0.1))
	# El pivote de muñeca es el UNICO nodo que rota. Antes el mismo `recoil_rot`
	# se escribia tambien en recoil_node, que es su hijo, asi que la jerarquia
	# componia el giro DOS veces: el angulo que llegaba al arma era el doble del
	# pedido. Ahora cada nodo tiene una sola responsabilidad y la composicion es
	# exacta: p -> R(rot)·(p - muñeca) + muñeca + pos.
	#   wrist_pivot -> la capa de retroceso completa (rotacion sobre la muñeca
	#                  + traslacion, las dos en el marco del arma)
	#   recoil_node  -> desplazamiento fijo que lleva el origen al punto de la
	#                  muñeca, para que la rotacion ocurra ahi
	# Con rot=0 y pos=0 los dos se cancelan y el conjunto queda exactamente en el
	# origen de pose_root, que es lo que asume la pose de ADS resuelta una vez en
	# _solve_ads(). (Escribir solo `recoil_pos` aqui desplazaba el arma 12 cm.)
	wrist_pivot.position = wrist_local + recoil_pos
	wrist_pivot.rotation = recoil_rot
	recoil_node.position = -wrist_local
	recoil_node.rotation = Vector3.ZERO

	# Capa 3: brazos y viewmodel entero, más lento y blando.
	var arm_pos := Springs.vector(arm_recoil_pos, arm_recoil_vel, 90.0, 15.2, delta)
	arm_recoil_pos = arm_pos[0]
	arm_recoil_vel = arm_pos[1]
	var arm_rot := Springs.vector(arm_recoil_rot, arm_recoil_rot_vel, 90.0, 15.2, delta)
	arm_recoil_rot = arm_rot[0]
	arm_recoil_rot_vel = arm_rot[1]
	arm_recoil_pos = Vector3(clampf(arm_recoil_pos.x, -0.02, 0.02), clampf(arm_recoil_pos.y, -0.02, 0.02), clampf(arm_recoil_pos.z, -0.02, 0.03))
	arm_recoil_rot = Vector3(clampf(arm_recoil_rot.x, -0.08, 0.08), 0.0, clampf(arm_recoil_rot.z, -0.04, 0.04))


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
		recoil_vel += Vector3(0.0, -0.012, 0.040)
		recoil_rot_vel.x -= 0.14
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
	if reloading or not arms_ok:
		return
	_play_arms_anim("Inspect")


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
	_blend_to_idle(0.14)
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
	var ads_pose_rot := ads_rot
	var sprint_rot := Vector3(deg_to_rad(-14.0), deg_to_rad(-5.0), deg_to_rad(5.0))

	var carry_pos := hip_pos.lerp(sprint_pos, sprint_blend)
	var carry_rot := hip_rot.lerp(sprint_rot, sprint_blend)
	var pos := carry_pos.lerp(ads_pos, aim_blend)
	var rot := carry_rot.lerp(ads_pose_rot, aim_blend)

	var move_norm := clampf(player_speed / 4.35, 0.0, 1.0)
	pos.x += cos(bob_phase * 0.5) * 0.0045 * move_norm + sway.x * (1.0 - aim_blend * 0.65)
	pos.y += sin(bob_phase) * 0.0065 * move_norm + sin(idle_phase * 1.05) * 0.0016 * (1.0 - aim_blend * 0.55) + sway.y * (1.0 - aim_blend * 0.65)
	var move_x := clampf(_last_local_move.x, -1.0, 1.0)
	var move_y := clampf(_last_local_move.y, -1.0, 1.0)
	pos.x -= move_x * 0.02 * (1.0 - aim_blend * 0.5)
	pos.y -= absf(move_y) * 0.008 * (1.0 - aim_blend * 0.5)

	pos += arm_recoil_pos
	rot += arm_recoil_rot
	rot.x += sway.y * 0.5 + sin(idle_phase * 1.05) * 0.0025 * (1.0 - aim_blend * 0.6) - move_y * 0.008
	rot.y += sway.x * 0.5 + sin(idle_phase * 0.73 + 1.0) * 0.0020 * (1.0 - aim_blend * 0.6)
	rot.z += -move_x * 0.012 - sin(bob_phase) * 0.012 * sprint_blend
	# El tope tiene que dejar pasar la pose de ADS: la pistola sube desde la
	# postura baja de descanso hasta la mira sin quedar recortada.
	# El limite sigue existiendo para el balanceo, el bob y el retroceso, que son
	# los que podian desmadrar el arma.
	pos.x = clampf(pos.x, -0.30, 0.30)
	pos.y = clampf(pos.y, -0.30, maxf(0.18, ads_pos.y))
	pos.z = clampf(pos.z, minf(-0.45, ads_pos.z), 0.15)
	# El límite del balanceo no debe recortar una inclinación ADS elegida por
	# captura: la pose de apuntado puede necesitar más de 20° para que el cañón
	# quede apenas por debajo del frente, mientras hip y el retroceso conservan
	# el límite corto.
	var rot_limit := maxf(0.35, absf(ads_pose_rot.x) + 0.015)
	rot.x = clampf(rot.x, -rot_limit, rot_limit)
	rot.y = clampf(rot.y, -0.35, 0.35)
	rot.z = clampf(rot.z, -0.25, 0.25)

	# Pose de recarga: sube y gira el arma para que el brocal entre en pantalla.
	# Las manos van en el mismo rig, así que suben con ella: no hay desincronía.
	pos.y += reload_pose_blend * RELOAD_POSE_UP
	pos.z += reload_pose_blend * RELOAD_POSE_FWD
	rot.x += reload_pose_blend * RELOAD_POSE_PITCH
	rot.z += reload_pose_blend * RELOAD_POSE_ROLL
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
	shell.global_transform = ejection_port.global_transform
	var basis := ejection_port.global_transform.basis
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


## Construye el viewmodel: el arma del asset como UNICA arma. Sin rig legacy,
## sin mallas ocultas, sin esqueletos de soporte: la corredera y el gatillo los
## mueve la logica sobre los huesos (ver _apply_pistol_parts) y las manos las
## mueve la animacion del autor (ver _install_arms).
func _build_viewmodel() -> void:
	# El arma visible es la del asset de primera persona: aqui solo se prepara
	# su marco. La mira, la boca y el fogonazo (que si son de FlowFire) se
	# montan sobre la corredera real en _install_arms.
	_build_high_fidelity_pistol()
	print("GLOCK arma=asset 9mm 1Matzh")


func _solve_ads() -> void:
	if sight_marker == null or front_marker == null or camera == null:
		return
	(sight_marker as Node3D).force_update_transform()
	(front_marker as Node3D).force_update_transform()
	(pose_root as Node3D).force_update_transform()
	(self as Node3D).force_update_transform()
	camera.force_update_transform()
	# Todo en espacio de Glock: el WeaponRig cuelga de la camara, asi que la
	# pose resuelta aqui acompaña a la respiracion y al bob sin perder el cero.
	var glock_inv: Transform3D = (self as Node3D).global_transform.affine_inverse()
	var rear_g: Vector3 = glock_inv * (sight_marker as Node3D).global_position
	var front_g: Vector3 = glock_inv * (front_marker as Node3D).global_position
	var eye_g: Vector3 = glock_inv * camera.global_position
	var axis_g: Vector3 = (glock_inv.basis * -camera.global_transform.basis.z).normalized()
	var sight_dir: Vector3 = (front_g - rear_g).normalized()
	# El "arriba" del arma es el eje Y de la corredera (hueso Slidder), no el UP
	# del nodo: el Idle del asset sostiene la pistola con ~16 grados de canto
	# (MEDIDO con --gundiag) y nivelar el nodo dejaba la corredera torcida en
	# ADS. La referencia es el arma real.
	var slide_up_g: Vector3 = (glock_inv.basis * (arms_skeleton.global_transform.basis * arms_skeleton.get_bone_global_pose(slide_bone).basis).y).normalized()
	# Rotacion minima que lleva la linea de mira al eje, mas correccion de
	# balanceo para que la corredera quede vertical (sin canto).
	var rot := Basis.IDENTITY
	var cross := sight_dir.cross(axis_g)
	if cross.length() > 0.00001 and absf(sight_dir.dot(axis_g)) < 0.99999:
		rot = Basis(cross.normalized(), sight_dir.angle_to(axis_g)) * rot
	var up_after: Vector3 = (rot * slide_up_g).normalized()
	var cam_up_g: Vector3 = (glock_inv.basis * camera.global_transform.basis.y).normalized()
	var up_proj: Vector3 = cam_up_g - axis_g * cam_up_g.dot(axis_g)
	if up_proj.length() > 0.001 and up_after.length() > 0.001:
		up_proj = up_proj.normalized()
		var roll_axis: Vector3 = axis_g
		var a := atan2(up_after.cross(up_proj).dot(roll_axis), up_after.dot(up_proj))
		rot = Basis(roll_axis, a) * rot
	var target_rear: Vector3 = eye_g + axis_g * ADS_SIGHT_DISTANCE
	# La pose rota sobre el origen de pose_root: primero rota el alza, luego se
	# traslada hasta su punto. Exacto para cadenas rigidas, sin iterar.
	var origin_g: Vector3 = glock_inv * (pose_root as Node3D).global_position
	var rear_rotated: Vector3 = origin_g + (rot * (rear_g - origin_g))
	ads_offset = target_rear - rear_rotated
	ads_rot = rot.get_euler()
	print("ADS_GEOMETRICO offset=", ads_offset.snapped(Vector3(0.001, 0.001, 0.001)),
		" rot_deg=", (ads_rot * 180.0 / PI).snapped(Vector3(0.1, 0.1, 0.1)),
		" linea_mira=", sight_dir.snapped(Vector3(0.001, 0.001, 0.001)))


func get_sight_world_position() -> Vector3:
	if sight_marker != null:
		return sight_marker.global_position
	return global_position


func get_front_sight_world_position() -> Vector3:
	if front_marker != null:
		return front_marker.global_position
	return get_sight_world_position()
## ---------------------------------------------------------------------------
## Brazos + arma del asset (un solo rig): la pose humana.
##
## El rig trae animaciones CON los brazos y el arma ya agarrada (Idle/Fire/
## Reload x2/Inspect...): no hay retargeting ni IK. El conjunto se cuelga bajo
## RecoilNode con giro 180 en Y (el modelo apunta a +Z, la camara a -Z) y
## escala uniforme CALIBRADA (ver ARMS_SCALE); la posicion lleva la empunadura
## al ancla. La pose la manda la animacion del autor.
##
## Solo se dibuja el personaje: el skybox de presentacion (AABB 2x2) y los
## ayudantes de apuntado (4 caras) se apagan. Los guantes y las mangas se
## matizan a tela oscura conservando sus texturas (ver _darken_arms).
## ---------------------------------------------------------------------------
const ARMS_PATH := "res://assets/models/full9mm_2k.glb"
# Escala uniforme del conjunto. Valor CALIBRADO de FlowFire para el encuadre
# (el asset esta modelado ~1:1 en metros: corredera 29.4 mm como una real).
const ARMS_SCALE := 1.362
# Punto de la empunadura en espacio de recoil que fija el encuadre de cadera
# validado, y distancia hueso-arma -> punto de referencia hacia la boca.
# Son el ancla del montaje, no geometria medida: el ADS los ignora (lo resuelve
# _solve_ads desde la mira real).
const GRIP_ANCHOR := Vector3(0.0, -0.088, 0.038)
const GRIP_AHEAD := 0.080

var arms_mount: Node3D  # soporte estatico bajo RecoilNode (escala uniforme)
var arms_root: Node3D
var arms_skeleton: Skeleton3D
var arms_player: AnimationPlayer
var arms_mesh_visible: MeshInstance3D  # manos (para diagnostico y benchmark)
var arms_sleeve_visible: MeshInstance3D  # antebrazos/mangas (idem)
var arms_ok := false


## ---------------------------------------------------------------------------
## Arma de alta fidelidad: la del propio asset, sin piezas paralelas.
##
## Aqui solo se crea el marco (GunFrame, referencia espacial bajo el retroceso).
## La mira trasera/delantera, la boca y el puerto cuelgan de la CORREDERA REAL
## (hueso Slidder_919) via BoneAttachment3D en _install_arms: se mueven con la
## animacion y con la logica porque SON el arma, no una copia. El fogonazo se
## construye alli mismo, sobre la boca real.
## ---------------------------------------------------------------------------
var pistol_holder: Node3D  # marco del arma bajo RecoilNode (referencia espacial)
var pistol_ok := false  # true cuando los huesos mecanicos estan listos

## Crea el marco del arma. El arma visible es la del asset de primera persona,
## que trae su pistola con las manos ya agarradas y sus animaciones.
func _build_high_fidelity_pistol() -> bool:
	var holder := Node3D.new()
	holder.name = "GunFrame"
	recoil_node.add_child(holder)
	pistol_holder = holder
	pistol_ok = false
	return true


func _install_arms() -> void:
	if pistol_holder == null:
		push_error("Falta el soporte del viewmodel")
		return
	var packed := load(ARMS_PATH) as PackedScene
	if packed == null:
		push_warning("No se pudieron cargar los brazos: " + ARMS_PATH)
		return
	arms_root = packed.instantiate()
	arms_root.name = "Arms1Matzh"
	arms_skeleton = arms_root.find_child("Skeleton3D", true, false) as Skeleton3D
	arms_player = arms_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if arms_skeleton == null or arms_player == null:
		push_warning("Los brazos no traen esqueleto utilizable")
		arms_root.queue_free()
		arms_root = null
		return
	# La raiz del GLB trae su propia rotacion de Sketchfab: no se sobrescribe
	# su transform, se cuelga bajo el soporte y se mueve el soporte.
	var holder := Node3D.new()
	holder.name = "ArmsMount"
	recoil_node.add_child(holder)
	holder.add_child(arms_root)
	arms_mount = holder

	# TODAS las mallas se dibujan: este rig trae brazos Y arma ya montada y
	# animada. Solo se apaga el skybox de presentacion (AABB 2x2) y los
	# ayudantes de apuntado, que no son personaje.
	var meshes := _collect_meshes(arms_root)
	var hidden := 0
	var arms_best: MeshInstance3D = null
	var arms_most := -1
	for m in meshes:
		# Skybox de presentacion y ayudantes de apuntado: fuera. El skybox se
		# detecta por su AABB de 2x2; los ayudantes por tener 4 caras.
		var sz := (m.mesh as Mesh).get_aabb().size
		var tris := 0
		if m.mesh is ArrayMesh:
			for si in range(m.mesh.get_surface_count()):
				var ar: Array = m.mesh.surface_get_arrays(si)
				if ar.size() > 0 and ar[Mesh.ARRAY_INDEX] != null:
					tris += (ar[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		# Fuera: skybox de presentacion (AABB 2x2) y ayudantes de apuntado
		# (4 caras). La pistola del asset SI se dibuja: es el arma de FlowFire.
		var rn: String = m.mesh.resource_name
		# El arma del propio pack se reconoce por el HUESO que la mueve (mucho
		# mas fiable que el nombre de la malla, que el importador renombra).
		# Solo el skybox de presentacion (AABB 2x2) y los ayudantes de apuntado
		# (4 caras) se apagan. La pistola del asset SI se dibuja: es el arma
		# visible de FlowFire, con sus animaciones.
		if (sz.x > 1.5 and sz.z > 1.5) or tris <= 16:
			m.visible = false
			hidden += 1
			continue
		# La malla de BRAZOS es la que deforman huesos de mano o antebrazo. NO
		# vale elegir la de mas vertices: medido, este asset tiene una malla de
		# 8 474 verts que no son los brazos, y el diagnostico medía esa.
		var dom := _dominant_bone(m)
		if (dom.findn("hand") >= 0 or dom.findn("forearm") >= 0 or dom.findn("arm") >= 0) and _mesh_vert_count(m) > arms_most:
			arms_most = _mesh_vert_count(m)
			arms_best = m
	arms_mesh_visible = arms_best
	# Mangas: la otra malla de brazos (antebrazos). Hace falta para matizar su
	# tela (venia con metallic=1.0 de importacion y salia blanca) y para el
	# diagnostico por familias.
	for m in meshes:
		if m.visible and m != arms_best:
			var dom2 := _dominant_bone(m)
			if dom2.findn("forearm") >= 0 or dom2.findn("arm") >= 0:
				arms_sleeve_visible = m
				break
	for m in meshes:
		print("  MALLA ", m.name, " mesh=", m.mesh.resource_name, " visible=", m.visible, " tris~", 0, " dom=", _dominant_bone(m))
	print("ARMS_MALLAS total=", meshes.size(), " ocultas=", hidden,
		" brazos=", arms_best.name if arms_best else "NINGUNA",
		" verts=", arms_most)

	_park_arms("Idle", 0.0)
	var weapon_bone := _exact_bone(WEAPON_BONE)
	var barrel_bone := _exact_bone(BARREL_BONE)
	var mag_bone := _exact_bone(MAG_BONE)
	slide_bone = _exact_bone(SLIDE_BONE)
	trigger_bone = _exact_bone(TRIGGER_BONE)
	if weapon_bone < 0 or barrel_bone < 0 or mag_bone < 0 or slide_bone < 0 or trigger_bone < 0:
		push_warning("El rig no trae los huesos del arma (Weapon/Barrel/Magazine/Slidder/Trigger)")
		holder.queue_free(); arms_root = null; return
	# El modelo apunta a +Z y la camara mira a -Z: giro 180 en Y. Asi el alza
	# delantera queda al fondo y la trasera cerca, como en su propia vista FPS.
	# La posicion lleva el punto de referencia de la empunadura al ancla: es lo
	# unico que fija el encuadre de cadera (residuo 0 por construccion).
	arms_scale = ARMS_SCALE
	var scaled_r := Basis(Vector3.UP, PI).scaled(Vector3(arms_scale, arms_scale, arms_scale))
	var weapon_in_skel := arms_skeleton.get_bone_global_pose(weapon_bone).origin
	var barrel_in_skel := arms_skeleton.get_bone_global_pose(barrel_bone).origin
	var grip_ref: Vector3 = weapon_in_skel + (barrel_in_skel - weapon_in_skel).normalized() * GRIP_AHEAD
	holder.transform = Transform3D(scaled_r, GRIP_ANCHOR - scaled_r * grip_ref)
	var grip_err: float = (holder.transform * grip_ref - GRIP_ANCHOR).length() * 1000.0
	print("ARMS_MONTAJE escala=", snappedf(arms_scale, 0.0001),
		" residuo_empunadura_mm=", snappedf(grip_err, 0.1))
	# Reposos mecanicos: la pose local sin animar de corredera y gatillo.
	slide_rest = arms_skeleton.get_bone_rest(slide_bone).origin
	trigger_rest = arms_skeleton.get_bone_rest(trigger_bone).origin
	_mount_slide_attachments()
	_strip_mechanical_tracks()
	_measure_wrist(weapon_bone)
	# La pistola visible es la del propio asset y ya viene montada y animada en
	# su esqueleto, asi que no hay segunda arma que colgar.
	_darken_arms()
	arms_ok = true
	pistol_ok = true
	_play_arms_anim("Idle", true)
	print("ARMS_1MATZH ok manos_mandan anim=", arms_player.get_animation_list())
	if camera != null and not ads_solved:
		_solve_ads()


## Todas las mallas bajo una raiz.
func _collect_meshes(root_node: Node) -> Array:
	var out: Array = []
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _mesh_vert_count(mi: MeshInstance3D) -> int:
	var c := 0
	for si in range(mi.mesh.get_surface_count()):
		c += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return c


## Hueso con mas peso acumulado en la malla (su dueño de facto).
func _dominant_bone(mi: MeshInstance3D) -> String:
	var acc := {}
	for si in range(mi.mesh.get_surface_count()):
		var arrays := mi.mesh.surface_get_arrays(si)
		if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
			continue
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for vi in range(n):
			for k in range(4):
				var w: float = weights[vi * 4 + k]
				if w > 0.0:
					var b: int = bones[vi * 4 + k]
					acc[b] = float(acc.get(b, 0.0)) + w
	var best := -1
	var best_w := 0.0
	for b in acc:
		if float(acc[b]) > best_w:
			best_w = float(acc[b])
			best = b
	if best < 0 or arms_skeleton == null:
		return ""
	return arms_skeleton.get_bone_name(best)


func _find_bone(prefix: String) -> int:
	for b in range(arms_skeleton.get_bone_count()):
		if arms_skeleton.get_bone_name(b).begins_with(prefix):
			return b
	return -1


## Hueso por nombre exacto (los del arma). Sin prefijos afortunados.
func _exact_bone(bone_name: String) -> int:
	return arms_skeleton.find_bone(bone_name)


## Mira trasera/delantera, boca y puerto SOBRE la corredera real: un
## BoneAttachment3D sigue al hueso Slidder cada frame sin codigo por frame, asi
## que el ADS, el fogonazo, la balistica y la vaina leen el arma de verdad
## (incluido su retroceso de corredera) en vez de una copia fija.
func _mount_slide_attachments() -> void:
	var att := BoneAttachment3D.new()
	att.name = "SlideAttach"
	att.bone_idx = slide_bone
	arms_skeleton.add_child(att)
	slide_attach = att
	sight_marker = _attach_point(att, "SightRear", SIGHT_REAR_SLIDE)
	front_marker = _attach_point(att, "SightFront", SIGHT_FRONT_SLIDE)
	muzzle = _attach_point(att, "Muzzle", MUZZLE_SLIDE)
	ejection_port = _attach_point(att, "EjectionPort", EJECT_SLIDE)
	# El fogonazo cuelga de la boca real: su presentación vive en WeaponFX.gd.
	fx = WeaponFX.new()
	fx.name = "WeaponFX"
	muzzle.add_child(fx)
	fx.build()
	print("ARMS_MIRA corredera_real lista, flash_en_boca")


func _attach_point(parent: Node3D, point_name: String, offset: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = point_name
	parent.add_child(n)
	n.position = offset
	return n


## La logica es la unica autoridad de corredera, gatillo y RETROCESO DEL ARMA:
## las pistas que los animaban se eliminan al cargar.
##
##  - Slidder_919 y Weapon_Trigger_921 en Fire, Reload y Reload_Empty: sin esto
##    habria dos correderas, la simulada (slide_pos, 59 ms) y la animada
##    (33.6 mm en 250 ms).
##  - Weapon_922 SOLO en Fire (rotacion y traslacion): MEDIDO con --firecurve,
##    la animacion del autor sube el arma 0.24 grados en los primeros 40 ms y
##    luego la levanta en rampa casi lineal hasta 14 grados a 180 ms. Eso es un
##    gesto dibujado, no un impulso: el arma se quedaba clavada justo cuando la
##    corredera ya habia ido y vuelto, y por eso el casquillo parecia tener mas
##    movimiento que la pistola. El arma visible pasa a moverse solo por la
##    fisica (ver _update_recoil), con la animacion aportando el gesto humano
##    (manos, munecas, brazos). Las pistas del cargador y del canon se quedan:
##    son parte de ese gesto y no hay autoridad que las contradiga.
func _strip_mechanical_tracks() -> void:
	var clips := ["Fire", "Reload", "Reload_Empty"]
	for short_name in clips:
		var resolved := ""
		for candidate in arms_player.get_animation_list():
			if candidate == short_name or candidate.ends_with("|" + short_name):
				resolved = candidate
				break
		if resolved == "":
			continue
		var anim: Animation = arms_player.get_animation(resolved)
		var targets := [SLIDE_BONE, TRIGGER_BONE]
		if short_name == "Fire":
			targets.append(WEAPON_BONE)
		var removed := 0
		for ti in range(anim.get_track_count() - 1, -1, -1):
			var tp := str(anim.track_get_path(ti))
			for b in targets:
				if tp.contains(":" + b):
					anim.remove_track(ti)
					removed += 1
					break
		print("ARMS_PISTA ", resolved, " mecanicas_eliminadas=", removed)


## Pivote del retroceso procedural: punto de la mano que sostiene el arma
## (35% del hueso del arma hacia el hueso de la mano), medido en el rig NUEVO
## en Idle. Antes era el origen por defecto (giro sobre el centro del arma).
func _measure_wrist(weapon_bone: int) -> void:
	var hand := _exact_bone("DEF-hand.R_842")
	if hand < 0:
		return
	arms_skeleton.force_update_all_bone_transforms()
	var inv: Transform3D = (recoil_node as Node3D).global_transform.affine_inverse()
	var skel_xf: Transform3D = arms_skeleton.global_transform
	var weapon_p: Vector3 = inv * (skel_xf * arms_skeleton.get_bone_global_pose(weapon_bone).origin)
	var hand_p: Vector3 = inv * (skel_xf * arms_skeleton.get_bone_global_pose(hand).origin)
	wrist_local = weapon_p + (hand_p - weapon_p) * 0.35
	print("ARMS_MUNECA pivote=", wrist_local.snapped(Vector3(0.001, 0.001, 0.001)))


## Deja una animacion de brazos aparcada en un instante exacto (medicion).
func _park_arms(short_name: String, t: float) -> bool:
	if arms_player == null:
		return false
	for candidate in arms_player.get_animation_list():
		if candidate == short_name or candidate.ends_with("|" + short_name):
			arms_player.play(candidate)
			arms_player.seek(t, true)
			arms_skeleton.force_update_all_bone_transforms()
			return true
	return false
## Guantes y mangas como TELA/CUERO, conservando las texturas del autor.
##
## El asset trae difusas reales (costuras, nudillos, tejido) y una textura
## ORM donde el canal metalico del guante esta a 0.99, con lo que el material
## sale cromado: reflejaba las luces del viewmodel como plastico negro pulido.
## La tela y el cuero son dielectricos, asi que el cambio minimo es el que se
## hace aqui: se tine el albedo (multiplica la difusa; el detalle sigue) y se
## fuerza un DIELECTRICO con specular bajo y el emisivo del autor apagado (el
## guante trae emissiveFactor=1.0 con una textura casi negra: no aporta nada y
## bajo el glow del bodycam solo puede ensuciar las costuras).
##
## No se toca ninguna luz de la escena: un material que no es metal no puede
## arreglarse iluminando menos.
const FABRIC_SPECULAR := 0.22  # dieléctrico de tela/cuero, no barniz
const GLOVE_TINT := Color(0.52, 0.52, 0.55, 1.0)
const SLEEVE_TINT := Color(0.40, 0.40, 0.43, 1.0)
const GLOVE_ROUGHNESS := 0.95
const SLEEVE_ROUGHNESS := 1.0


func _darken_arms() -> void:
	_darken_mesh(arms_mesh_visible, "ARMS_GUANTE", GLOVE_TINT, GLOVE_ROUGHNESS)
	_darken_mesh(arms_sleeve_visible, "ARMS_MANGA", SLEEVE_TINT, SLEEVE_ROUGHNESS)


func _darken_mesh(mi: MeshInstance3D, label: String, tint: Color, roughness: float) -> void:
	if mi == null or mi.mesh == null:
		return
	for si in range(mi.mesh.get_surface_count()):
		var m: Material = mi.get_surface_override_material(si)
		if m == null:
			m = mi.mesh.surface_get_material(si)
		if m is StandardMaterial3D:
			var src := m as StandardMaterial3D
			var fabric := src.duplicate() as StandardMaterial3D
			fabric.albedo_color = tint
			# Dieléctrico: el canal metalico del ORM (0.99) no manda sobre la tela.
			fabric.metallic = 0.0
			fabric.metallic_specular = FABRIC_SPECULAR
			fabric.roughness = roughness
			fabric.emission_enabled = false
			mi.set_surface_override_material(si, fabric)
			print(label, " superficie ", si,
				" albedo_tex=", src.albedo_texture != null,
				" mr_tex=", src.metallic_texture != null,
				" normal_tex=", src.normal_texture != null,
				" metallic_origen=", src.metallic,
				" -> dielectrico rough=", roughness, " tinte=", tint)


func _play_arms_anim(short_name: String, loop := false) -> bool:
	if not arms_ok or arms_player == null:
		return false
	var resolved := ""
	for candidate in arms_player.get_animation_list():
		if candidate == short_name or candidate.ends_with("|" + short_name):
			resolved = candidate
			break
	if resolved == "":
		return false
	arms_player.play(resolved, -1.0, 1.0)
	if not loop:
		var idle := _resolve_arms_idle()
		if idle != "":
			arms_player.queue(idle)
	return true


func _resolve_arms_idle() -> String:
	if arms_player == null:
		return ""
	for candidate in arms_player.get_animation_list():
		if candidate == "Idle" or candidate.ends_with("|Idle"):
			return candidate
	return ""
func _apply_pistol_parts() -> void:
	if not pistol_ok or arms_skeleton == null or slide_bone < 0:
		return
	var ratio := SLIDE_VISUAL_TRAVEL / SLIDE_TRAVEL
	arms_skeleton.set_bone_pose_position(slide_bone, slide_rest + Vector3(0.0, 0.0, -slide_pos * ratio))
	if trigger_bone >= 0:
		arms_skeleton.set_bone_pose_position(trigger_bone, trigger_rest + TRIGGER_PULL * trigger_visual)
	# Cargador: sin escritura por frame. Lo lleva la mano en la animacion de
	# recarga, en fase con las manos por construccion; la logica solo cuenta
	# cartuchos en los instantes medidos (ver _seat_reload_mag).
