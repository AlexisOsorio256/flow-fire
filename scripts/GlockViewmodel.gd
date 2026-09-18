class_name GlockViewmodel
extends Node3D

## VIEWMODEL: los brazos animados, el arma montada y la pose de camara.
##
## NO decide gameplay. Recibe el estado ya decidido por `Glock.gd` y lo
## representa.
##
## CADENA DE NODOS
##
##   Viewmodel
##   └── PoseRoot            cadera / ADS / sprint / bob / sway / respiracion
##       └── WristPivot      cesion lenta de brazos y manos (GlockRecoil.arm_*)
##           ├── ArmsMount   anclaje de los brazos; dentro, Skeleton3D + clips
##           ├── HandGrip    el arma dentro del pivote
##           │   └── WeaponSocket   retroceso: UNICA transformacion del arma
##           │       └── Grip -> Frame/Slide/Trigger/Magazine/Muzzle/...
##           └── HandSocket  cuelga del hueso de la mano izquierda (el cargador)
##
## AUTORIDAD (una sola por cosa; nada de dos capas sobre el mismo transform)
##
##   Brazos, manos, dedos, gestos ... AnimationPlayer (los clips del asset)
##   El arma entera (recoil) ........ WeaponSocket, escrito por GlockRecoil
##   Corredera y gatillo ............ Glock.gd -> GlockWeapon
##   Cargador ....................... Glock.gd -> HandSocket / arma
##   Camara ......................... Player.gd (aqui no se toca)
##
## EL ARMA NO ESTA EN EL ESQUELETO, ni se busca dentro de el: `GlockWeapon` es un
## arbol de piezas rigidas y su sitio son DOS CONSTANTES CALIBRADAS, no una
## medicion en runtime. Los brazos son `assets/models/arms.glb`, ya podado por
## `tools/prune_arms.py`: trae solo las mallas del personaje, los 78 huesos que
## las deforman y los cinco clips que el juego reproduce.
##
## Los clips mueven las MANOS; la pistola del autor estaba anclada en el espacio
## (solo giraba, no seguia a la muneca), asi que el arma va anclada igual: fija
## al pivote, con las manos del clip trabajando alrededor. Eso es lo que se ve.

## Brazos en uso. El .glb lo prepara tools/prune_arms.py sobre el rig de 1Matzh.
const ARMS_PATH := "res://assets/models/arms.glb"
## Anclaje de los brazos. CALIBRADO una vez sobre el encuadre validado en :0:
## giro 180 en Y (el modelo mira a +Z), escala para que la mano mida lo que la
## pistola, y la posicion que deja la muneca donde se ve bien.
const ARMS_SCALE := 1.362
const ARMS_MOUNT_POS := Vector3(-0.035304, -2.155700, 0.580815)
## El arma dentro del pivote. CALIBRADO igual, sobre el rig original: pone la
## boca del cargador de nuestra Glock en la union del agarre del autor y la deja
## apuntando como el apuntaba. Radianes.
const GRIP_POS := Vector3(0.029968, -0.114451, 0.095923)
const GRIP_ROT := Vector3(0.086880, 0.039442, -0.020152)
## Pose de cadera (verificada en :0).
## Estilo bodycam: derecha-abajo-lejos para que el arma no tape los blancos.
const HIP_POS := Vector3(0.15, -0.015, -0.42)
## Ojo -> mira trasera en ADS.
const ADS_SIGHT_DISTANCE := 0.44
## Pose de recarga: el arma sube al centro-bajo y se inclina para ensenar el
## brocal; el objetivo queda libre (verificado en :0).
const RELOAD_POSE_UP := 0.10
const RELOAD_POSE_RIGHT := 0.0
const RELOAD_POSE_FWD := 0.03
const RELOAD_POSE_PITCH := 0.22
const RELOAD_POSE_ROLL := -0.15

const VIEWMODEL_LAYER := 13
const VIEWMODEL_LAYER_BIT := 1 << (VIEWMODEL_LAYER - 1)

var camera: Camera3D

# --- nodos del rig ---------------------------------------------------------
var pose_root: Node3D
var wrist_pivot: Node3D
var hand_grip: Node3D
var weapon_socket: Node3D
var viewmodel_light: OmniLight3D

# --- arma y brazos ---------------------------------------------------------
var weapon: GlockWeapon
var arms_mount: Node3D
var arms_root: Node3D
var arms_skeleton: Skeleton3D
var arms_player: AnimationPlayer
var arms_ok := false

# --- cargador: socket en la mano izquierda ---------------------------------
var hand_socket: BoneAttachment3D
var _hand_bone := -1
var _mag_home: Node = null
var _mag_in_hand := false

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
	wrist_pivot = Node3D.new()
	wrist_pivot.name = "WristPivot"
	pose_root.add_child(wrist_pivot)
	hand_grip = Node3D.new()
	hand_grip.name = "HandGrip"
	wrist_pivot.add_child(hand_grip)
	weapon_socket = Node3D.new()
	weapon_socket.name = "WeaponSocket"
	hand_grip.add_child(weapon_socket)
	_build_viewmodel_light()


## Monta el rig completo: arma de piezas + brazos animados.
func mount() -> void:
	_install_weapon()
	_install_arms()


# ---------------------------------------------------------------------------
# ARMA
# ---------------------------------------------------------------------------
func _install_weapon() -> void:
	weapon = GlockWeapon.new()
	weapon.name = "Weapon"
	weapon_socket.add_child(weapon)
	weapon.build()
	if weapon.frame == null:
		weapon = null
		return
	# La pistola nace donde el arma tenga su origen (la boca del cargador) y el
	# sitio exacto lo pone el anclaje de abajo, que es comun para las dos.
	muzzle = weapon.muzzle
	ejection_port = weapon.ejection_port
	_apply_viewmodel_layer(weapon)
	if recoil != null:
		recoil.set_pivot(Vector3.ZERO)


# ---------------------------------------------------------------------------
# BRAZOS
# ---------------------------------------------------------------------------
## Monta los brazos. El asset trae SOLO las mallas del personaje (mangas,
## guantes, reloj), los huesos que las deforman y los clips: nada que
## clasificar, nada que apagar y ningun hueso de pistola que interpretar.
func _install_arms() -> void:
	var packed := load(ARMS_PATH) as PackedScene
	if packed == null:
		push_warning("No se pudieron cargar los brazos: " + ARMS_PATH)
		return
	arms_root = packed.instantiate()
	arms_root.name = "Arms"
	arms_skeleton = arms_root.find_child("Skeleton3D", true, false) as Skeleton3D
	arms_player = arms_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if arms_skeleton == null or arms_player == null:
		push_warning("Los brazos no traen esqueleto utilizable")
		arms_root.queue_free()
		arms_root = null
		return
	arms_mount = Node3D.new()
	arms_mount.name = "ArmsMount"
	wrist_pivot.add_child(arms_mount)
	arms_mount.add_child(arms_root)
	_apply_viewmodel_layer(arms_root)
	arms_mount.position = ARMS_MOUNT_POS
	arms_mount.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	arms_mount.scale = Vector3.ONE * ARMS_SCALE
	# El arma, en su sitio del pivote (no del hueso): las manos del clip giran a
	# su alrededor, que es como se animo el asset original.
	hand_grip.position = GRIP_POS
	hand_grip.rotation = GRIP_ROT
	hand_grip.scale = Vector3.ONE * ARMS_SCALE

	_mount_hand_socket()
	_darken_arms()
	arms_ok = true
	play_anim("Idle", true)
	if camera != null and not ads_solved:
		solve_ads()


func _mount_hand_socket() -> void:
	_hand_bone = arms_skeleton.find_bone("Hand_L")
	if _hand_bone < 0:
		push_warning("El rig de brazos no trae el hueso Hand_L")
		return
	hand_socket = BoneAttachment3D.new()
	hand_socket.name = "HandSocket"
	hand_socket.bone_idx = _hand_bone
	arms_skeleton.add_child(hand_socket)
	_apply_viewmodel_layer(hand_socket)


func hand_bone_index() -> int:
	return _hand_bone


## El cargador pasa a la mano. El offset se mide AHORA, con la pose real del
## frame: el cargador queda donde la mano lo agarra, sin numeros de ajuste.
func magazine_to_hand() -> void:
	if weapon == null or weapon.magazine == null or hand_socket == null:
		return
	if _mag_in_hand:
		return
	arms_skeleton.force_update_all_bone_transforms()
	hand_socket.force_update_transform()
	var mano := hand_socket.global_transform
	var mag := weapon.magazine.global_transform
	hand_socket.transform = mano.affine_inverse() * mag
	_mag_home = weapon.magazine.get_parent()
	# Conservar el global: el socket cuelga del esqueleto (otra escala) y con
	# keep=false el cargador heredaria su tamano multiplicado.
	weapon.magazine.reparent(hand_socket, true)
	_mag_in_hand = true


## El cargador vuelve al arma (al brocal), en su sitio exacto de reposo.
func magazine_to_weapon() -> void:
	if not _mag_in_hand or weapon == null or weapon.magazine == null:
		return
	if _mag_home != null:
		weapon.magazine.reparent(_mag_home, false)
		weapon.magazine.position = weapon.magazine_rest
		weapon.magazine.rotation = Vector3.ZERO
		weapon.magazine.scale = Vector3.ONE
	_mag_in_hand = false


func magazine_in_hand() -> bool:
	return _mag_in_hand


# ---------------------------------------------------------------------------
# Materiales y capas
# ---------------------------------------------------------------------------
const FABRIC_SPECULAR := 0.22
const GLOVE_TINT := Color(0.52, 0.52, 0.55, 1.0)
const SLEEVE_TINT := Color(0.40, 0.40, 0.43, 1.0)
const GLOVE_ROUGHNESS := 0.95
const SLEEVE_ROUGHNESS := 1.0


## Tinte de tela del bodycam: los guantes y las mangas van apagados y mates.
func _darken_arms() -> void:
	if arms_root == null:
		return
	_darken_mesh(arms_root.find_child("Gloves", true, false) as MeshInstance3D,
		GLOVE_TINT, GLOVE_ROUGHNESS)
	_darken_mesh(arms_root.find_child("Sleeves", true, false) as MeshInstance3D,
		SLEEVE_TINT, SLEEVE_ROUGHNESS)


func _darken_mesh(mi: MeshInstance3D, tint: Color, roughness: float) -> void:
	if mi == null or mi.mesh == null:
		return
	for si in range(mi.mesh.get_surface_count()):
		var m: Material = mi.mesh.surface_get_material(si)
		if m is StandardMaterial3D:
			var fabric := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			fabric.albedo_color = tint
			fabric.metallic = 0.0
			fabric.metallic_specular = FABRIC_SPECULAR
			fabric.roughness = roughness
			fabric.emission_enabled = false
			mi.set_surface_override_material(si, fabric)


## Todo el viewmodel va a su propia capa: el post del bodycam y las luces del
## mundo no lo tocan.
func _apply_viewmodel_layer(root_node: Node) -> void:
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = VIEWMODEL_LAYER_BIT
		for c in n.get_children():
			stack.append(c)


func _build_viewmodel_light() -> void:
	viewmodel_light = OmniLight3D.new()
	viewmodel_light.name = "ViewmodelKey"
	viewmodel_light.light_color = Color(0.94, 0.96, 1.0)
	viewmodel_light.light_energy = 2.9
	viewmodel_light.omni_range = 1.5
	viewmodel_light.omni_attenuation = 1.35
	viewmodel_light.shadow_enabled = false
	viewmodel_light.light_cull_mask = VIEWMODEL_LAYER_BIT
	viewmodel_light.position = Vector3(-0.30, 0.26, 0.42)
	pose_root.add_child(viewmodel_light)

	var fill := OmniLight3D.new()
	fill.name = "ViewmodelFill"
	fill.light_color = Color(0.95, 0.97, 1.0)
	fill.light_energy = 0.95
	fill.omni_range = 1.3
	fill.omni_attenuation = 1.2
	fill.shadow_enabled = false
	fill.light_cull_mask = VIEWMODEL_LAYER_BIT
	fill.position = Vector3(0.28, -0.08, 0.46)
	pose_root.add_child(fill)


# ---------------------------------------------------------------------------
# Animacion
# ---------------------------------------------------------------------------
## Los clips del rig llevan el nombre a secas: Idle, Fire, Reload, Reload_Empty,
## Inspect. Los pide Glock.gd por su nombre.
func play_anim(nombre: String, loop := false) -> bool:
	if not arms_ok or arms_player == null or not arms_player.has_animation(nombre):
		push_warning("El rig de brazos no trae el clip " + nombre)
		return false
	arms_player.play(nombre, -1.0, 1.0)
	if not loop and arms_player.has_animation("Idle"):
		arms_player.queue("Idle")
	return true


func play_fire() -> void:
	play_anim("Fire")


func play_reload(empty: bool) -> void:
	play_anim("Reload_Empty" if empty else "Reload")


func blend_to_idle(blend: float) -> void:
	if arms_player != null and arms_player.has_animation("Idle"):
		arms_player.play("Idle", blend)


# ---------------------------------------------------------------------------
# Pose y estado por frame
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
		recoil.apply(wrist_pivot, weapon_socket)


# ---------------------------------------------------------------------------
# ADS geometrico y camara
# ---------------------------------------------------------------------------
func setup(cam: Camera3D) -> void:
	camera = cam
	if arms_ok and not ads_solved:
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


func get_sight_world_position() -> Vector3:
	if weapon != null and weapon.sight_rear != null:
		return weapon.sight_rear.global_position
	return global_position


func get_front_sight_world_position() -> Vector3:
	if weapon != null and weapon.sight_front != null:
		return weapon.sight_front.global_position
	return get_sight_world_position()
