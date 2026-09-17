class_name GlockViewmodel
extends Node3D

## VIEWMODEL: el rig de brazos, el montaje del arma y la pose de camara.
##
## NO decide gameplay. Recibe el estado ya decidido por `Glock.gd` y lo
## representa.
##
## CADENA DE NODOS
##
##   Viewmodel
##   └── PoseRoot            cadera / ADS / sprint / bob / sway / respiracion
##       └── WristPivot      cesion lenta de brazos y manos (GlockRecoil.arm_*)
##           ├── ArmsMount   escala + anclaje del rig de brazos (GLB)
##           │   └── Skeleton3D + AnimationPlayer
##           └── HandGrip    posicion del arma respecto del pivote
##               └── WeaponSocket   retroceso: UNICA transformacion del arma
##                   └── Grip -> Frame/Slide/Trigger/Magazine/Muzzle/...
##
## AUTORIDAD (una sola por cosa; nada de dos capas sobre el mismo transform)
##
##   Brazos, manos, dedos, gestos ... AnimationPlayer (clips del autor)
##   El arma entera (recoil) ........ WeaponSocket, escrito por GlockRecoil
##   Corredera ...................... Glock.gd -> GlockWeapon.set_slide()
##   Gatillo ........................ Glock.gd -> GlockWeapon.set_trigger()
##   Cargador ....................... Glock.gd -> HandSocket / arma
##   Camara ......................... Player.gd (aqui no se toca)
##
## EL ARMA YA NO ESTA EN EL ESQUELETO. Es `GlockWeapon`, un arbol de piezas
## rigidas. Por eso este archivo no escribe ni un hueso del arma, y por eso
## `WristPivot` puede mover a la vez brazos y pistola: la pose de las manos la
## pone el clip, y como el pivote es antepasado comun, la pistola la sigue sin
## ningun seguimiento por codigo. Cero desincronizacion mano<->arma.
##
## EL CARGADOR no depende de tiempos escritos a mano: `Glock.gd` decide cuando
## la mano lo tiene y llama a `magazine_to_hand()` / `magazine_to_weapon()`.
## `HandSocket` cuelga del hueso de la mano con un offset que se mide en el
## instante del agarre, asi que el cargador viaja con la mano de verdad.

const ARMS_PATH := "res://assets/models/full9mm_2k.glb"
## Escala y anclaje del rig de brazos, CALIBRADOS sobre el encuadre validado.
const ARMS_SCALE := 1.362
const GRIP_ANCHOR := Vector3(0.0, -0.088, 0.038)
const GRIP_AHEAD := 0.080
## Punto del arma que se lleva al ancla del agarre, en espacio LOCAL del arma.
##
## El origen de la pieza Frame ES la empunadura: el armazon de Urpo nace en la
## union empunadura-corredera (el pivote del cabeceo se puso ahi a proposito,
## ver tools/make_weapon_parts.py). Por eso el arma se coloca con su origen en
## el ancla y no hace falta compensar nada.
##
## ES EL UNICO NUMERO QUE ENCUADRA EL ARMA. Si hay que subirla, bajarla,
## adelantarla o acercarla, se toca esta linea y nada mas.
const ARMA_EMPUNADURA := Vector3.ZERO
## Pose de cadera (validada).
const HIP_POS := Vector3(0.0, 0.122, -0.34)
## Ojo -> mira trasera en ADS.
const ADS_SIGHT_DISTANCE := 0.54
## Pose de recarga: sube y gira el arma para que el brocal entre en pantalla.
const RELOAD_POSE_UP := 0.075
const RELOAD_POSE_FWD := 0.045
const RELOAD_POSE_PITCH := 0.17
const RELOAD_POSE_ROLL := -0.30

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
var arms_mesh_visible: MeshInstance3D
var arms_sleeve_visible: MeshInstance3D
var arms_ok := false
var _arms_ref := Vector3.ZERO

# --- cargador --------------------------------------------------------------
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
var sight_marker: Node3D
var front_marker: Node3D
var ads_offset := Vector3(0.0, 0.15, -0.24)
var ads_rot := Vector3.ZERO
var ads_solved := false

var recoil: GlockRecoil  # estado del retroceso; se aplica en update()
var fire_clip := ""
var reload_clip := ""
var reload_empty_clip := ""
var inspect_clip := ""
var idle_clip := ""


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
	# La empunadura del arma al ancla del agarre. Una sola constante, un solo
	# sitio: mover el arma en pantalla es tocar ARMA_EMPUNADURA.
	weapon.position = GRIP_ANCHOR - ARMA_EMPUNADURA * weapon.escala
	# Los puntos del arma (boca, puerto) ya cuelgan de su corredera.
	muzzle = weapon.muzzle
	ejection_port = weapon.ejection_port
	_apply_viewmodel_layer(weapon)
	if recoil != null:
		recoil.set_pivot(Vector3.ZERO)


# ---------------------------------------------------------------------------
# BRAZOS
# ---------------------------------------------------------------------------
## El rig de brazos es el asset de 1Matzh (CC-BY 4.0), pero aqui SOLO se usan
## sus brazos: la malla de la pistola que trae dentro se apaga, porque el arma
## visible es `GlockWeapon`. Las animaciones se reproducen integras (el arma ya
## no esta en el esqueleto, asi que sus pistas de hueso no hacen nada).
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
	var holder := Node3D.new()
	holder.name = "ArmsMount"
	wrist_pivot.add_child(holder)
	holder.add_child(arms_root)
	arms_mount = holder
	_apply_viewmodel_layer(arms_root)

	# Solo se dibuja el personaje: se apaga el skybox y los ayudantes, y sobre
	# todo la MALLA DE LA PISTOLA del asset (el arma visible es la de piezas).
	var ocultas := 0
	for m in _collect_meshes(arms_root):
		if not _es_personaje(m):
			m.visible = false
			ocultas += 1
			continue
		if _es_brazos(m) and (arms_mesh_visible == null or _mesh_vert_count(m) > _mesh_vert_count(arms_mesh_visible)):
			arms_mesh_visible = m
	for m in _collect_meshes(arms_root):
		if m.visible and m != arms_mesh_visible and _es_mangas(m):
			arms_sleeve_visible = m
			break

	park_anim("Idle", 0.0)
	# Anclaje del rig: giro 180 en Y (el modelo mira a +Z) y escala uniforme.
	var scaled_r := Basis(Vector3.UP, PI).scaled(Vector3(ARMS_SCALE, ARMS_SCALE, ARMS_SCALE))
	_arms_ref = _referencia_empunadura()
	holder.transform = Transform3D(scaled_r, GRIP_ANCHOR - scaled_r * _arms_ref)

	fire_clip = _resolve_clip("Fire")
	reload_clip = _resolve_clip("Reload")
	reload_empty_clip = _resolve_clip("Reload_Empty")
	inspect_clip = _resolve_clip("Inspect")
	idle_clip = _resolve_clip("Idle")
	_mount_hand_socket()
	_darken_arms()
	arms_ok = true
	play_anim("Idle", true)
	print("BRAZOS ok mallas_ocultas=", ocultas, " clips=", arms_player.get_animation_list())
	if camera != null and not ads_solved:
		solve_ads()


## Punto de referencia de la empunadura DENTRO del rig de brazos: el centro de
## la malla de la pistola que trae el asset. Como esa malla coincide con el arma
## que montamos encima, anclar aqui deja las dos en el mismo sitio.
func _referencia_empunadura() -> Vector3:
	var mejor: MeshInstance3D = null
	for m in _collect_meshes(arms_root):
		if _es_personaje(m) and not _es_brazos(m) and not _es_mangas(m):
			if mejor == null or _mesh_vert_count(m) > _mesh_vert_count(mejor):
				mejor = m
	if mejor == null:
		return Vector3.ZERO
	var caja: AABB = mejor.mesh.get_aabb()
	var centro := caja.get_center()
	# La empunadura esta en la mitad inferior de la pistola.
	return Vector3(centro.x, caja.position.y, centro.z)


func _es_personaje(m: MeshInstance3D) -> bool:
	var sz: Vector3 = (m.mesh as Mesh).get_aabb().size
	if sz.x > 1.5 and sz.z > 1.5:
		return false
	return _mesh_vert_count(m) > 16


## Malla de brazos: la que deforman huesos de mano o antebrazo.
func _es_brazos(m: MeshInstance3D) -> bool:
	var d := _dominant_bone(m)
	return d.findn("hand") >= 0 or d.findn("forearm") >= 0


func _es_mangas(m: MeshInstance3D) -> bool:
	var d := _dominant_bone(m)
	return d.findn("forearm") >= 0 or d.findn("upper_arm") >= 0


# ---------------------------------------------------------------------------
# CARGADOR: socket en la mano
# ---------------------------------------------------------------------------
## Cuelga un punto del hueso de la mano izquierda. El offset real se mide en el
## primer agarre (ver Glock.gd), no se inventa aqui.
func _mount_hand_socket() -> void:
	_hand_bone = _find_left_hand_bone()
	if _hand_bone < 0:
		return
	hand_socket = BoneAttachment3D.new()
	hand_socket.name = "HandSocket"
	hand_socket.bone_idx = _hand_bone
	arms_skeleton.add_child(hand_socket)
	_apply_viewmodel_layer(hand_socket)


## Busca la mano izquierda sin depender del sufijo numerico del importador.
func _find_left_hand_bone() -> int:
	if arms_skeleton == null:
		return -1
	var best := -1
	var best_score := -1
	for i in range(arms_skeleton.get_bone_count()):
		var n := arms_skeleton.get_bone_name(i).to_lower()
		if not n.contains("hand"):
			continue
		if not (n.contains(".l") or n.contains("_l") or n.contains("-l") or n.contains("left")):
			continue
		var score := 1
		if n.contains("def"):
			score += 4
		if n.begins_with("def-hand"):
			score += 3
		if score > best_score:
			best = i
			best_score = score
	return best


func hand_bone_index() -> int:
	return _hand_bone


## El cargador pasa a la mano. El offset se calcula AHORA, con la pose real del
## frame: asi no hay ningun numero magico y funciona con cualquier animacion.
func magazine_to_hand() -> void:
	if weapon == null or weapon.magazine == null or hand_socket == null:
		return
	if _mag_in_hand:
		return
	arms_skeleton.force_update_all_bone_transforms()
	hand_socket.force_update_transform()
	# Offset mano->cargador medido en ESTE instante: el cargador queda donde la
	# mano lo agarra, sin ningun numero escrito a mano.
	var mano := hand_socket.global_transform
	var mag := weapon.magazine.global_transform
	hand_socket.transform = mano.affine_inverse() * mag
	_mag_home = weapon.magazine.get_parent()
	weapon.magazine.reparent(hand_socket, false)
	_mag_in_hand = true


## El cargador vuelve al arma (al brocal), en su sitio exacto de reposo.
func magazine_to_weapon() -> void:
	if not _mag_in_hand or weapon == null or weapon.magazine == null:
		return
	if _mag_home != null:
		weapon.magazine.reparent(_mag_home, false)
		weapon.magazine.position = weapon.magazine_rest
	_mag_in_hand = false


func magazine_in_hand() -> bool:
	return _mag_in_hand


# ---------------------------------------------------------------------------
# Materiales y utilidades de malla
# ---------------------------------------------------------------------------
const FABRIC_SPECULAR := 0.22
const GLOVE_TINT := Color(0.52, 0.52, 0.55, 1.0)
const SLEEVE_TINT := Color(0.40, 0.40, 0.43, 1.0)
const GLOVE_ROUGHNESS := 0.95
const SLEEVE_ROUGHNESS := 1.0


func _darken_arms() -> void:
	_darken_mesh(arms_mesh_visible, "GUANTE", GLOVE_TINT, GLOVE_ROUGHNESS)
	_darken_mesh(arms_sleeve_visible, "MANGA", SLEEVE_TINT, SLEEVE_ROUGHNESS)


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
			fabric.metallic = 0.0
			fabric.metallic_specular = FABRIC_SPECULAR
			fabric.roughness = roughness
			fabric.emission_enabled = false
			mi.set_surface_override_material(si, fabric)


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
func _resolve_clip(short_name: String) -> String:
	if arms_player == null:
		return ""
	for candidate in arms_player.get_animation_list():
		if candidate == short_name or candidate.ends_with("|" + short_name):
			return candidate
	return ""


func play_anim(short_name: String, loop := false) -> bool:
	if not arms_ok or arms_player == null:
		return false
	var resolved := _resolve_clip(short_name)
	if resolved == "":
		return false
	arms_player.play(resolved, -1.0, 1.0)
	if not loop and idle_clip != "":
		arms_player.queue(idle_clip)
	return true


func park_anim(short_name: String, t: float) -> bool:
	var resolved := _resolve_clip(short_name)
	if resolved == "":
		return false
	arms_player.play(resolved)
	arms_player.seek(t, true)
	arms_skeleton.force_update_all_bone_transforms()
	return true


func play_fire() -> void:
	play_anim("Fire")


func play_reload(empty: bool) -> void:
	play_anim("Reload_Empty" if empty else "Reload")


func blend_to_idle(blend: float) -> void:
	if arms_player == null or idle_clip == "":
		return
	arms_player.play(idle_clip, blend)


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
