class_name GlockViewmodel
extends Node3D

## VIEWMODEL: la pistola montada, los brazos y la pose de camara. Los brazos son
## una capa de presentacion; no participan en la mecanica.
##
## NO decide gameplay. Recibe el estado ya decidido por `Glock.gd` y lo
## representa.
##
## CADENA DE NODOS
##
##   Viewmodel
##   └── PoseRoot          cadera / ADS / sprint / bob / sway / respiracion
##       └── BodyGive      cesion lenta del conjunto (GlockRecoil.give_*)
##           ├── ArmsRig   fps_arms.glb: 1 malla, esqueleto deform, 5 clips
##           └── WeaponGrip  el arma dentro del pivote (GRIP_POS / GRIP_ROT)
##               └── WeaponSocket   retroceso: UNICA transformacion del arma
##                   └── Weapon -> Frame / Slide / Barrel / Magazine / ...
##
## AUTORIDAD (una sola por cosa; nada de dos capas sobre el mismo transform)
##
##   El arma entera (recoil) ........ WeaponSocket, escrito por GlockRecoil
##   Corredera, gatillo y cargador .. Glock.gd -> GlockWeapon
##   Huesos humanos ................. AnimationPlayer de ArmsRig, y SOLO huesos
##   Camara ......................... Player.gd (aqui no se toca)
##
## LOS BRAZOS NO ESCRIBEN EL TRANSFORM DEL ARMA. `ArmsRig` cuelga de `BodyGive`,
## asi que recibe la cesion lenta del conjunto pero NO el retroceso rapido: el
## arma cabecea dentro del agarre, que es lo que se quiere leer. Quien pide los
## clips es `Glock.gd`, en sus propios hitos: la animacion no tiene cronometros
## ni estado, y no puede convertirse en una segunda autoridad mecanica.
##
## EL ARMA NO ESTA EN NINGUN ESQUELETO, ni se busca dentro de uno: `GlockWeapon`
## es un arbol de piezas rigidas.
##
## ESCALA: el arma va en metros (malla 174 mm; referencia Gen5 185 mm, se
## declara aproximacion visual). Nadie la escala para encuadrar; el encuadre se
## calibra alrededor.

## El arma dentro del pivote.
##
## SON IDENTIDAD A PROPOSITO. El asset de brazos se autora en el espacio del arma
## (mismo sistema que el GLB de la Glock) con la mano ya agarrando la
## empuñadura, asi que no hay desplazamiento que compensar: `mount_arms()` iguala
## la raiz del brazo a la del arma con UNA operacion medida, no con una constante
## calibrada a ojo. Si la malla del brazo cambia, este archivo no se toca.
const GRIP_POS := Vector3(0.0, 0.0, 0.0)
const GRIP_ROT := Vector3(0.0, 0.0, 0.0)
## Pose de cadera (verificada en :0).
## Estilo bodycam: derecha-abajo-lejos para que el arma no tape los blancos.
## CALIBRADO con la pistola en metros reales. La distancia final al ojo es la
## suma del rig (`Player.WEAPON_RIG_POS.z`) y de esta pose; el numero que manda
## es el que mide `tools/frame_probe.tscn` (0,653 m en cadera), no esta linea.
## ACERCADO: el encuadre anterior dejaba el arma a 0,653 m del ojo (suma de
## `Player.WEAPON_RIG_POS.z` y esta pose), que a 82 grados de FOV la dibuja como
## un 12% del alto de cuadro: se lee lejos para una pistola que se lleva en la
## mano. Ahora esta a 0,52 m, que es la distancia de un viewmodel normal y ademas
## queda coherente con el ADS (0,44 m). El encuadre real lo mide
## `tools/frame_probe.tscn`; este numero no se toca a ojo.
const HIP_POS := Vector3(0.095, -0.011, -0.130)
## Ojo -> mira trasera en ADS.
const ADS_SIGHT_DISTANCE := 0.44
## Pose de recarga: el arma sube al centro-bajo, se canta hacia dentro para
## ensenar el brocal y se acerca al cuerpo, que es como se recarga de verdad.
## Antes eran 10 cm de subida y 8 grados de cante: el arma practicamente no se
## movia y la recarga se leia como un cargador deslizandose solo. El brocal
## tiene que quedar mirando al suelo, delante del tirador. El golpe del asiento
## se suma como una excursion NEGATIVA de esta misma pose: el arma se hunde un
## pelo cuando el cargador entra.
const RELOAD_POSE_UP := 0.14
const RELOAD_POSE_RIGHT := -0.035
const RELOAD_POSE_FWD := 0.085
const RELOAD_POSE_PITCH := 0.30
const RELOAD_POSE_ROLL := -0.42
## INSPECCION: pose PROPIA, no la de recarga. El puerto de expulsion esta en el
## lado DERECHO de la corredera y la camara esta detras-izquierda y arriba del
## arma (vector arma->camara en cadera, medido con `tools/frame_probe.tscn`:
## (-0,16, +0,28, +0,94)). Subir el arma no ensena nada: el puerto solo encara al
## ojo con guiñada NEGATIVA (el morro se va a la derecha del tirador y la ventana
## gira hacia su cara). Antes la inspeccion reutilizaba la pose de recarga y el
## puerto miraba hacia fuera: la recamara no se veia, que es justo lo unico que
## la inspeccion tiene que ensenar.
## La subida es PEQUENA a proposito. Subir y acercar el arma mete el antebrazo
## en cuadro: los brazos van soldados a la pose del arma, asi que levantar el
## arma levanta el brazo entero y la mano acaba tapando la corredera (medido en
## captura: a +0,12 de subida y +0,13 de avance la mano llenaba el encuadre y el
## arma quedaba detras). En la pose de cadera, que es la que funciona, el
## antebrazo sale por abajo-derecha; la inspeccion se queda cerca de ahi.
const INSPECT_POSE_UP := 0.05
const INSPECT_POSE_RIGHT := -0.05
const INSPECT_POSE_FWD := 0.02
const INSPECT_POSE_PITCH := 0.06
## La guiñada es GRANDE y no es un adorno: con el arma a 0,56 m y la camara
## detras, el puerto (normal +X del arma) solo encara al ojo cerca de -85 grados.
## Se midio: a -39 grados el puerto daba +0,46 contra el ojo (oblicuo); con este
## valor pasa de +0,9. `tools/frame_probe.tscn` imprime los numeros.
const INSPECT_POSE_YAW := -1.45
const INSPECT_POSE_ROLL := -0.20
## ACOPLAMIENTO CON EL ASSET DE BRAZOS, declarado para que nadie lo rompa en
## silencio: los brazos van soldados a la pose del arma, asi que el clip
## `Inspect` lleva dentro la CONTRARROTACION de esta guiñada. Si se cambia
## INSPECT_POSE_YAW/PITCH/ROLL aqui, hay que cambiar los mismos tres numeros en
## `tools/build_arms.py` (constantes INSPECT_PITCH/YAW/ROLL de su cabecera) y
## reexportar. No es una preferencia estetica: sin la contrarrotacion el
## antebrazo cruza el encuadre y tapa el arma.
## Los offsets de posicion (UP/RIGHT/FWD) NO necesitan ese espejo: mueven el
## arma y el brazo juntos, no cambian su orientacion relativa.

const VIEWMODEL_LAYER := 13
const VIEWMODEL_LAYER_BIT := 1 << (VIEWMODEL_LAYER - 1)

## BRAZOS: un unico asset de produccion, montado en `BodyGive`. Su fuente y su
## contrato estan en `CREDITS_MODELS.md`; su builder, en `tools/build_arms.py`.
##
## El asset se autora en el ESPACIO DEL ARMA (mismo sistema que `g19_pistol.glb`:
## +Y arriba, -Z al morro, origen en la raiz del arma) con la mano derecha ya
## agarrando la empuñadura. Por eso al montar solo hay que igualar la raiz del
## brazo a la del arma: no hay offsets que calibrar en runtime, y si la malla
## cambia, el encuadre no se toca.
const ARMS_PATH := "res://assets/models/fps_arms.glb"
const CLIP_IDLE := "Idle"
const CLIP_FIRE := "Fire"
const CLIP_RELOAD := "Reload"
const CLIP_RELOAD_EMPTY := "ReloadEmpty"
const CLIP_INSPECT := "Inspect"

var camera: Camera3D

# --- nodos del rig ---------------------------------------------------------
var pose_root: Node3D
var body_give: Node3D
var weapon_grip: Node3D
var weapon_socket: Node3D

# --- arma ------------------------------------------------------------------
var weapon: GlockWeapon

# --- brazos ----------------------------------------------------------------
var arms_rig: Node3D
var arms_player: AnimationPlayer
var _clip := ""

# --- puntos del arma -------------------------------------------------------
var muzzle: Node3D:
	get:
		return weapon.muzzle if weapon != null else null
var ejection_port: Node3D:
	get:
		return weapon.ejection_port if weapon != null else null

# --- estado de pose (lo escribe Glock una vez por frame) --------------------
var _in_aim := 0.0
var _in_sprint := 0.0
var _in_speed := 0.0
var _in_look := Vector2.ZERO
var _in_move := Vector2.ZERO
var _in_reload_pose := 0.0
var _in_inspect_pose := 0.0

var bob_phase := 0.0
var idle_phase := 0.0
var sway := Vector2.ZERO
var ads_offset := Vector3(0.0, 0.15, -0.24)
var ads_rot := Vector3.ZERO
var ads_solved := false

var recoil: GlockRecoil  # estado del retroceso; se aplica en update()


func _ready() -> void:
	pose_root = Node3D.new()
	pose_root.name = "PoseRoot"
	add_child(pose_root)
	body_give = Node3D.new()
	body_give.name = "BodyGive"
	pose_root.add_child(body_give)
	weapon_grip = Node3D.new()
	weapon_grip.name = "WeaponGrip"
	body_give.add_child(weapon_grip)
	weapon_socket = Node3D.new()
	weapon_socket.name = "WeaponSocket"
	weapon_grip.add_child(weapon_socket)
	_build_viewmodel_light()


## Monta el arma y los brazos en el mismo espacio de Grip. Ninguno de los dos
## assets contiene animacion de mecanica: los brazos SOLO mueven huesos humanos,
## y el WeaponSocket es el unico que mueve la Glock entera durante el recoil.
func mount() -> bool:
	weapon = GlockWeapon.new()
	weapon.name = "Weapon"
	weapon_socket.add_child(weapon)
	if not weapon.build():
		push_error("Viewmodel detenido: el GLB canonico de Glock no monta")
		weapon.queue_free()
		weapon = null
		return false
	weapon_grip.position = GRIP_POS
	weapon_grip.rotation = GRIP_ROT
	if not mount_arms():
		return false
	muzzle = weapon.muzzle
	ejection_port = weapon.ejection_port
	_apply_viewmodel_layer(weapon)
	if recoil != null:
		recoil.set_pivot(weapon.grip_pivot())
	return true


## Los brazos son una capa de PRESENTACION, y son obligatorios: si faltan, el
## viewmodel no arranca en vez de dibujar una pistola flotante. El contrato de
## produccion lo dice: si falta un asset obligatorio, el arranque falla.
func mount_arms() -> bool:
	var packed := load(ARMS_PATH) as PackedScene
	if packed == null:
		push_error("Viewmodel detenido: falta el asset de brazos " + ARMS_PATH)
		return false
	var instance := packed.instantiate() as Node3D
	if instance == null:
		push_error("Viewmodel detenido: " + ARMS_PATH + " no tiene raiz Node3D")
		return false
	# La raiz importada se cuelga de un portanodos, y es EL PORTANODOS el que se
	# calibra. Escribir sobre la raiz importada borraria la transformacion que le
	# haya puesto el importador (hoy es identidad, pero eso es un detalle del
	# importador, no un contrato del asset).
	var holder := Node3D.new()
	holder.name = "ArmsRig"
	body_give.add_child(holder)
	holder.add_child(instance)
	arms_rig = holder
	# El arma esta en reposo en este instante (WeaponGrip y WeaponSocket son
	# identidad), asi que su transform de mundo ES el espacio del arma. Se iguala
	# con una operacion, no con una constante calibrada: cambiar la malla del
	# brazo no obliga a tocar este archivo.
	pose_root.force_update_transform()
	body_give.force_update_transform()
	weapon.force_update_transform()
	arms_rig.transform = body_give.global_transform.affine_inverse() * weapon.global_transform
	arms_player = _find_player(arms_rig)
	if arms_player == null:
		push_error("Viewmodel detenido: los brazos no traen AnimationPlayer")
		return false
	for name in [CLIP_IDLE, CLIP_FIRE, CLIP_RELOAD, CLIP_RELOAD_EMPTY, CLIP_INSPECT]:
		if _clip_name(name) == "":
			push_error("Los brazos no traen el clip obligatorio " + name)
			return false
	var idle := arms_player.get_animation(_clip_name(CLIP_IDLE))
	if idle != null:
		idle.loop_mode = Animation.LOOP_LINEAR
	arms_player.animation_finished.connect(_on_clip_finished)
	play_clip(CLIP_IDLE, true)
	_apply_viewmodel_layer(arms_rig)
	## Los numeros se CUENTAN, no se escriben: este print decia "1 malla" fijo y
	## el asset siguiente trajo dos. Un log que afirma lo que no ha medido es la
	## misma mentira que un README desactualizado, solo que la lee menos gente.
	print("BRAZOS montados: mallas=", _mesh_count(), " clips=", arms_player.get_animation_list(),
		" huesos=", _bone_count())
	return true


## Nombre real del clip dentro del AnimationPlayer importado. El importador de
## glTF puede prefijarlo, asi que se busca por sufijo en vez de por igualdad.
func _clip_name(clip: String) -> String:
	if arms_player == null:
		return ""
	for candidate in arms_player.get_animation_list():
		var text := String(candidate)
		if text == clip or text.ends_with("/" + clip) or text.ends_with("|" + clip) \
				or text.ends_with("_" + clip):
			return text
	return ""


## Reproduce un clip de brazos. Lo llaman SIEMPRE los hitos de `Glock.gd`: el
## AnimationPlayer no decide nada, solo obedece. `restart` vuelve al frame 0
## (un disparo detras de otro tiene que reempezar el latigazo, no ignorarlo).
func play_clip(clip: String, restart := false) -> void:
	if arms_player == null:
		return
	var found := _clip_name(clip)
	if found == "":
		push_error("Los brazos no traen el clip " + clip)
		return
	if not restart and _clip == found and arms_player.is_playing():
		return
	_clip = found
	arms_player.play(found)


func _on_clip_finished(clip: StringName) -> void:
	if String(clip).ends_with(CLIP_FIRE):
		play_clip(CLIP_IDLE, true)


func _mesh_count() -> int:
	var stack: Array = [arms_rig]
	var total := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			total += 1
		for child in node.get_children():
			stack.append(child)
	return total


func _bone_count() -> int:
	var stack: Array = [arms_rig]
	var total := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Skeleton3D:
			total += (node as Skeleton3D).get_bone_count()
		for child in node.get_children():
			stack.append(child)
	return total


func _find_player(root_node: Node) -> AnimationPlayer:
	var stack: Array = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is AnimationPlayer:
			return node as AnimationPlayer
		for child in node.get_children():
			stack.append(child)
	return null


## Offset del cargador dentro del arma (metros). Lo decide `Glock.gd`.
func set_magazine_offset(offset_m: float) -> void:
	if weapon != null:
		weapon.set_magazine_offset(offset_m)


func set_magazine_visible(v: bool) -> void:
	if weapon != null:
		weapon.set_magazine_attached(v)


## Tumba del cargador durante la recarga (radianes). Lo decide Glock.gd.
func set_magazine_tumble(angle: float) -> void:
	if weapon != null:
		weapon.set_magazine_tumble(angle)


# ---------------------------------------------------------------------------
# Materiales y capas
# ---------------------------------------------------------------------------
## Todo el viewmodel va a su propia capa para aislar su KEY/FILL.
## Las luces del mundo SI lo tocan (light_cull_mask por defecto es todo) y el
## post bodycam (fullscreen sobre screen_texture) tambien lo procesa.
func _apply_viewmodel_layer(root_node: Node) -> void:
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = VIEWMODEL_LAYER_BIT
		for c in n.get_children():
			stack.append(c)


func _build_viewmodel_light() -> void:
	var key := OmniLight3D.new()
	key.name = "ViewmodelKey"
	key.light_color = Color(0.94, 0.96, 1.0)
	key.light_energy = 0.42
	key.omni_range = 1.5
	key.omni_attenuation = 1.35
	key.shadow_enabled = false
	key.light_cull_mask = VIEWMODEL_LAYER_BIT
	key.position = Vector3(-0.30, 0.26, 0.42)
	pose_root.add_child(key)

	var fill := OmniLight3D.new()
	fill.name = "ViewmodelFill"
	fill.light_color = Color(0.95, 0.97, 1.0)
	fill.light_energy = 0.22
	fill.omni_range = 1.3
	fill.omni_attenuation = 1.2
	fill.shadow_enabled = false
	fill.light_cull_mask = VIEWMODEL_LAYER_BIT
	fill.position = Vector3(0.28, -0.08, 0.46)
	pose_root.add_child(fill)


# ---------------------------------------------------------------------------
# Pose
# ---------------------------------------------------------------------------
func set_pose_inputs(aim: float, sprint: float, speed: float, look: Vector2, move: Vector2,
		reload_pose: float, inspect_pose := 0.0) -> void:
	_in_aim = aim
	_in_sprint = sprint
	_in_speed = speed
	_in_look = look
	_in_move = move
	_in_reload_pose = reload_pose
	_in_inspect_pose = inspect_pose


func _apply_pose(delta: float) -> void:
	idle_phase += delta

	var look_x := clampf(_in_look.x, -12.0, 12.0) * 0.0015
	var look_y := clampf(_in_look.y, -12.0, 12.0) * 0.0015
	sway.x += (-look_x - sway.x) * (1.0 - exp(-10.0 * delta))
	sway.y += (-look_y - sway.y) * (1.0 - exp(-10.0 * delta))
	sway.x = clampf(sway.x, -0.012, 0.012)
	sway.y = clampf(sway.y, -0.012, 0.012)

	if _in_speed > 0.25:
		bob_phase += delta * (1.8 + _in_speed * 1.45)

	var hip_pos := HIP_POS
	var ads_pos := ads_offset
	var sprint_pos := Vector3(0.05, -0.135, -0.02)
	var hip_rot := Vector3.ZERO
	var ads_pose_rot := ads_rot
	var sprint_rot := Vector3(deg_to_rad(-14.0), deg_to_rad(-5.0), deg_to_rad(5.0))

	var carry_pos := hip_pos.lerp(sprint_pos, _in_sprint)
	var carry_rot := hip_rot.lerp(sprint_rot, _in_sprint)
	var pos := carry_pos.lerp(ads_pos, _in_aim)
	var rot := carry_rot.lerp(ads_pose_rot, _in_aim)

	var move_norm := clampf(_in_speed / 4.35, 0.0, 1.0)
	pos.x += cos(bob_phase * 0.5) * 0.0045 * move_norm + sway.x * (1.0 - _in_aim * 0.65)
	pos.y += sin(bob_phase) * 0.0065 * move_norm + sin(idle_phase * 1.05) * 0.0016 * (1.0 - _in_aim * 0.55) + sway.y * (1.0 - _in_aim * 0.65)
	var move_x := clampf(_in_move.x, -1.0, 1.0)
	var move_y := clampf(_in_move.y, -1.0, 1.0)
	pos.x -= move_x * 0.02 * (1.0 - _in_aim * 0.5)
	pos.y -= absf(move_y) * 0.008 * (1.0 - _in_aim * 0.5)

	rot.x += sway.y * 0.5 + sin(idle_phase * 1.05) * 0.0025 * (1.0 - _in_aim * 0.6) - move_y * 0.008
	rot.y += sway.x * 0.5 + sin(idle_phase * 0.73 + 1.0) * 0.0020 * (1.0 - _in_aim * 0.6)
	rot.z += -move_x * 0.012 - sin(bob_phase) * 0.012 * _in_sprint

	pos.x = clampf(pos.x, -0.30, 0.30)
	pos.y = clampf(pos.y, -0.30, maxf(0.18, ads_pos.y))
	pos.z = clampf(pos.z, minf(-0.45, ads_pos.z), 0.15)
	var rot_limit := maxf(0.35, absf(ads_pose_rot.x) + 0.015)
	rot.x = clampf(rot.x, -rot_limit, rot_limit)
	rot.y = clampf(rot.y, -0.35, 0.35)
	rot.z = clampf(rot.z, -0.25, 0.25)

	pos.x += _in_reload_pose * RELOAD_POSE_RIGHT
	pos.y += _in_reload_pose * RELOAD_POSE_UP
	pos.z += _in_reload_pose * RELOAD_POSE_FWD
	rot.x += _in_reload_pose * RELOAD_POSE_PITCH
	rot.z += _in_reload_pose * RELOAD_POSE_ROLL
	pos.y += _in_inspect_pose * INSPECT_POSE_UP
	pos.x += _in_inspect_pose * INSPECT_POSE_RIGHT
	pos.z += _in_inspect_pose * INSPECT_POSE_FWD
	rot.x += _in_inspect_pose * INSPECT_POSE_PITCH
	rot.y += _in_inspect_pose * INSPECT_POSE_YAW
	rot.z += _in_inspect_pose * INSPECT_POSE_ROLL
	pose_root.position = pos
	pose_root.rotation = rot


func update(delta: float) -> void:
	_apply_pose(delta)
	if recoil != null:
		recoil.apply(body_give, weapon_socket)


# ---------------------------------------------------------------------------
# ADS geometrico y camara
# ---------------------------------------------------------------------------
func setup(cam: Camera3D) -> void:
	camera = cam
	if weapon != null and not ads_solved:
		solve_ads()


func solve_ads() -> void:
	if weapon == null or weapon.sight_rear == null or weapon.sight_front == null or camera == null:
		return
	(pose_root as Node3D).force_update_transform()
	(self as Node3D).force_update_transform()
	camera.force_update_transform()
	weapon.sight_rear.force_update_transform()
	weapon.sight_front.force_update_transform()
	var glock_inv: Transform3D = (self as Node3D).global_transform.affine_inverse()
	var rear_g: Vector3 = glock_inv * weapon.sight_rear.global_position
	var front_g: Vector3 = glock_inv * weapon.sight_front.global_position
	var eye_g: Vector3 = glock_inv * camera.global_position
	var axis_g: Vector3 = (glock_inv.basis * -camera.global_transform.basis.z).normalized()
	var sight_dir: Vector3 = (front_g - rear_g).normalized()
	# "Arriba" del arma: el eje Y de su propia corredera, no el del nodo.
	var slide_up_g: Vector3 = (glock_inv.basis * weapon.slide.global_transform.basis.y).normalized()
	var rot := Basis.IDENTITY
	var cross := sight_dir.cross(axis_g)
	if cross.length() > 0.00001 and absf(sight_dir.dot(axis_g)) < 0.99999:
		rot = Basis(cross.normalized(), sight_dir.angle_to(axis_g)) * rot
	var up_after: Vector3 = (rot * slide_up_g).normalized()
	var cam_up_g: Vector3 = (glock_inv.basis * camera.global_transform.basis.y).normalized()
	var up_proj: Vector3 = cam_up_g - axis_g * cam_up_g.dot(axis_g)
	if up_proj.length() > 0.001 and up_after.length() > 0.001:
		up_proj = up_proj.normalized()
		var a := atan2(up_after.cross(up_proj).dot(axis_g), up_after.dot(up_proj))
		rot = Basis(axis_g, a) * rot
	var target_rear: Vector3 = eye_g + axis_g * ADS_SIGHT_DISTANCE
	var origin_g: Vector3 = glock_inv * (pose_root as Node3D).global_position
	var rear_rotated: Vector3 = origin_g + (rot * (rear_g - origin_g))
	ads_offset = target_rear - rear_rotated
	ads_rot = rot.get_euler()
	ads_solved = true
	print("ADS offset=", ads_offset.snapped(Vector3(0.001, 0.001, 0.001)),
		" rot_deg=", (ads_rot * 180.0 / PI).snapped(Vector3(0.1, 0.1, 0.1)))
