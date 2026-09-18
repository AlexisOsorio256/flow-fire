class_name GlockViewmodel
extends Node3D

## VIEWMODEL: la pistola montada y la pose de camara. Sin brazos.
##
## NO decide gameplay. Recibe el estado ya decidido por `Glock.gd` y lo
## representa.
##
## CADENA DE NODOS
##
##   Viewmodel
##   └── PoseRoot          cadera / ADS / sprint / bob / sway / respiracion
##       └── BodyGive      cesion lenta del conjunto (GlockRecoil.give_*)
##           └── WeaponGrip    el arma dentro del pivote (GRIP_POS / GRIP_ROT)
##               └── WeaponSocket   retroceso: UNICA transformacion del arma
##                   └── Weapon -> Frame / Slide / Magazine / Muzzle / ...
##
## AUTORIDAD (una sola por cosa; nada de dos capas sobre el mismo transform)
##
##   El arma entera (recoil) ........ WeaponSocket, escrito por GlockRecoil
##   Corredera, gatillo y cargador .. Glock.gd -> GlockWeapon
##   Camara ......................... Player.gd (aqui no se toca)
##
## LOS BRAZOS NO ESTAN EN PRODUCCION. El asset de brazos (13,4 MB, 78 huesos y
## cinco clips que habia que remedir cada vez) esta congelado fuera del arbol:
## la pistola flota montada en el pivote y sigue siendo el hero asset. Cuando el
## arma este cerrada entraran unos brazos limpios como capa de presentacion, no
## como columna de la mecanica. Git conserva el asset y su podado.
##
## EL ARMA NO ESTA EN NINGUN ESQUELETO, ni se busca dentro de uno: `GlockWeapon`
## es un arbol de piezas rigidas y su sitio son DOS CONSTANTES CALIBRADAS
## (GRIP_POS / GRIP_ROT), no una medicion en runtime.
##
## ESCALA: el arma va en metros (malla 174 mm; referencia Gen5 185 mm, se
## declara aproximacion visual). Nadie la escala para encuadrar; el encuadre se
## calibra alrededor.

## El arma dentro del pivote. CALIBRADO mirando en :0 (origen 2026-09-17),
## menos 19,8 mm en X por el recentrado del GLB canonicalizado (el arma vieja
## venia desplazada -19,8 mm en X; el encuadre se conserva moviendo el pivote
## lo mismo en sentido contrario). Radianes.
const GRIP_POS := Vector3(0.010168, -0.114451, 0.095923)
const GRIP_ROT := Vector3(0.086880, 0.039442, -0.020152)
## Pose de cadera (verificada en :0).
## Estilo bodycam: derecha-abajo-lejos para que el arma no tape los blancos.
## CALIBRADO con la pistola en metros reales: la distancia al ojo es la de un
## encuadre validado (0,31 m), no la que exigia la escala inflada de los brazos.
const HIP_POS := Vector3(0.110, -0.011, -0.308)
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

const VIEWMODEL_LAYER := 13
const VIEWMODEL_LAYER_BIT := 1 << (VIEWMODEL_LAYER - 1)

var camera: Camera3D

# --- nodos del rig ---------------------------------------------------------
var pose_root: Node3D
var body_give: Node3D
var weapon_grip: Node3D
var weapon_socket: Node3D

# --- arma ------------------------------------------------------------------
var weapon: GlockWeapon

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


## Monta el arma en el pivote. Sin brazos: la pistola es todo el viewmodel.
func mount() -> void:
	weapon = GlockWeapon.new()
	weapon.name = "Weapon"
	weapon_socket.add_child(weapon)
	weapon.build()
	if weapon.frame == null:
		weapon = null
		return
	weapon_grip.position = GRIP_POS
	weapon_grip.rotation = GRIP_ROT
	muzzle = weapon.muzzle
	ejection_port = weapon.ejection_port
	_apply_viewmodel_layer(weapon)
	if recoil != null:
		recoil.set_pivot(weapon.grip_pivot())


## Cargador fuera del brocal, en metros (0 asentado). Lo decide Glock.gd.
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
	key.light_energy = 2.0
	key.omni_range = 1.5
	key.omni_attenuation = 1.35
	key.shadow_enabled = false
	key.light_cull_mask = VIEWMODEL_LAYER_BIT
	key.position = Vector3(-0.30, 0.26, 0.42)
	pose_root.add_child(key)

	var fill := OmniLight3D.new()
	fill.name = "ViewmodelFill"
	fill.light_color = Color(0.95, 0.97, 1.0)
	fill.light_energy = 1.4
	fill.omni_range = 1.3
	fill.omni_attenuation = 1.2
	fill.shadow_enabled = false
	fill.light_cull_mask = VIEWMODEL_LAYER_BIT
	fill.position = Vector3(0.28, -0.08, 0.46)
	pose_root.add_child(fill)


# ---------------------------------------------------------------------------
# Pose
# ---------------------------------------------------------------------------
func set_pose_inputs(aim: float, sprint: float, speed: float, look: Vector2, move: Vector2, reload_pose: float) -> void:
	_in_aim = aim
	_in_sprint = sprint
	_in_speed = speed
	_in_look = look
	_in_move = move
	_in_reload_pose = reload_pose


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
