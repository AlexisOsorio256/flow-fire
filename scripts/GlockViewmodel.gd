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
##           └── ArmsMount   escala + anclaje del rig de brazos (GLB)
##               └── Skeleton3D + AnimationPlayer
##                   └── WeaponAttachment (hueso Root del rig)
##                       └── HandGrip     bind + ajuste fijo de la pistola
##                           └── WeaponSocket   retroceso: unica transformacion dinamica
##                               └── Grip -> Frame/Slide/Trigger/Magazine/Muzzle/...
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
## rigidas. `WeaponAttachment` sigue el hueso `Root`, que el rig usa para el
## armazon de su pistola; `HandGrip` aplica su bind y el ajuste fijo. Asi los
## clips llevan el arma con la mano y `WeaponSocket` conserva el recoil sin
## escribir huesos ni seguir transforms por codigo.
##
## EL CARGADOR no depende de tiempos escritos a mano: `Glock.gd` decide cuando
## la mano lo tiene y llama a `magazine_to_hand()` / `magazine_to_weapon()`.
## `HandSocket` cuelga del hueso de la mano con un offset que se mide en el
## instante del agarre, asi que el cargador viaja con la mano de verdad.

## ARMA EN USO. Cambiar esta linea cambia de pistola: la tabla de armas
## (nombre, largo real, recorrido de corredera, capacidad) vive en
## scripts/GlockWeapon.gd. Valores: "glock", "de".
const ARMA := "glock"

const ARMS_PATH := "res://assets/models/fps_rig.glb"
const ARMS_MESH_NODE := "ArmModel"
## Malla skinneada de la pistola del autor. Se usa solo para tomar el bind de
## `Root` y luego se vacia sin apagar su nodo.
const ARMS_GUN_NODE := "Glock19"
const ARMS_WEAPON_BONE := "Root"
## La Glock nueva se normaliza a 0.125542 en GlockWeapon. Este factor la lleva
## al tamano 0.7785 con el que coincide con la pistola del rig, y se aplica al
## padre para conservar la escala mecanica propia de cada arma.
const WEAPON_RIG_SCALE := 6.2011
## La pistola del rig apunta a X; las piezas rigidas apuntan a -Z.
const ARMA_GIRO_RIG := -PI * 0.5
## Cotas reales de una Glock 19 (m): el ArmsMount se calibra midiendo la malla
## del autor y llevando su caja a estas cotas (ver `_measure_mesh` y
## `_align_arms_with_mesh`, portados de la calibracion probada de 928f256).
## Nada aqui es un numero magico: sale de la geometria real del GLB.
const GUN_LENGTH := 0.186
const GUN_TOP_OVER_ORIGIN := 0.035
## Pose de cadera (verificada en :0).
## Estilo bodycam: derecha-abajo-lejos para que el arma no tape los blancos.
const HIP_POS := Vector3(0.13, -0.06, -0.38)
## Ojo -> mira trasera en ADS.
const ADS_SIGHT_DISTANCE := 0.32
## Pose de recarga: el arma sube al centro-bajo y se inclina para
## ensenar el brocal; el objetivo queda libre (verificado en :0).
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
## Base medida del arma del autor (ver `_align_arms_with_mesh`).
var gun_frame_bind := Basis.IDENTITY
var bind_in_skeleton := Transform3D.IDENTITY


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
	weapon.build(ARMA)
	if weapon.frame == null:
		weapon = null
		return
	# La posicion definitiva la fija `_montar_arma_en_hueso` despues de montar
	# los brazos. Los puntos (boca, puerto) ya cuelgan de su corredera.
	muzzle = weapon.muzzle
	ejection_port = weapon.ejection_port
	_apply_viewmodel_layer(weapon)
	if recoil != null:
		recoil.set_pivot(Vector3.ZERO)


# ---------------------------------------------------------------------------
# BRAZOS
# ---------------------------------------------------------------------------
## Monta el rig sencillo (`fps_rig.glb`): brazos de 41 huesos y cuatro clips del
## autor. `Glock19` es una malla skinneada; sus huesos, no su nodo, se animan.
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

	arms_mesh_visible = arms_root.find_child(ARMS_MESH_NODE, true, false) as MeshInstance3D
	var arma_autor := arms_root.find_child(ARMS_GUN_NODE, true, false) as MeshInstance3D
	if arms_mesh_visible == null or arma_autor == null:
		push_warning("El rig no trae ArmModel o Glock19")
		return

	# Se conserva ArmModel por nombre: sus unidades no sirven para el filtro de
	# tamanos del rig anterior. Glock19 queda sin malla, pero mantiene su Skin para
	# convertir el bind del hueso Root al arma rigida.
	park_anim("Idle", 0.0)
	# El ArmsMount NO es un ancla inventada: se calibra midiendo la pistola del
	# autor (bind -> modelo) y llevando su caja a cotas reales de Glock 19.
	# Sin esto el esqueleto queda en unidades del GLB (escala 336x, metros de
	# deriva) y el ADS sale a varios metros.
	var medida := _measure_mesh(arma_autor)
	if medida.get("ok", false):
		_align_arms_with_mesh(medida, holder)
	else:
		push_warning("No se pudo medir la pistola del rig: anclaje por defecto")
		holder.transform = Transform3D.IDENTITY
	_montar_arma_en_hueso(arma_autor)
	arma_autor.mesh = null
	print("BRAZOS malla=", arms_mesh_visible.name, " arma_autor=", arma_autor.name)

	fire_clip = _resolve_clip("Shoot")
	reload_clip = _resolve_clip("Reload")
	reload_empty_clip = _resolve_clip("Reload")
	inspect_clip = _resolve_clip("Idle")
	idle_clip = _resolve_clip("Idle")
	_mount_hand_socket()
	_darken_arms()
	arms_ok = true
	play_anim("Idle", true)
	print("BRAZOS ok clips=", arms_player.get_animation_list())
	if camera != null and not ads_solved:
		solve_ads()


## Cuelga la cadena rigida del hueso Root. Su bind es la compensacion que el
## skin aplica al armazon del rig; sin el, un hijo rigido hereda la escala 336x
## del esqueleto y queda enorme.
func _montar_arma_en_hueso(arma_autor: MeshInstance3D) -> void:
	if weapon == null or arms_skeleton == null or arma_autor.skin == null:
		push_warning("No se pudo montar el arma: falta su Skin o el esqueleto")
		return
	var bone := arms_skeleton.find_bone(ARMS_WEAPON_BONE)
	var bind := -1
	for i in range(arma_autor.skin.get_bind_count()):
		if arma_autor.skin.get_bind_name(i) == ARMS_WEAPON_BONE:
			bind = i
			break
	if bone < 0 or bind < 0:
		push_warning("No se pudo montar el arma: falta el hueso o bind " + ARMS_WEAPON_BONE)
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponAttachment"
	attachment.bone_idx = bone
	arms_skeleton.add_child(attachment)
	hand_grip.reparent(attachment, false)
	var fit := Transform3D(Basis(Vector3.UP, ARMA_GIRO_RIG).scaled(Vector3.ONE * WEAPON_RIG_SCALE), Vector3.ZERO)
	hand_grip.transform = arma_autor.skin.get_bind_pose(bind) * fit
	# La empunadura no es el origen del GLB: se compensa con el basis completo
	# para que el giro del rig tambien afecte al desplazamiento.
	weapon.position = -(weapon.basis * weapon.empunadura)
	weapon.force_update_transform()
	print("ARMA anclada a ", ARMS_WEAPON_BONE, " escala_rig=", WEAPON_RIG_SCALE,
		" tamano_mundo=", _caja_mundo(weapon).size.snapped(Vector3(0.1, 0.1, 0.1)))


## MEDICION DEL RIG (portada de la calibracion probada de 928f256).
##
## El GLB viene en unidades propias: el `Skeleton3D` trae escala global 336x y
## `mesh.get_aabb()` en espacio de bind da cajas de cientos de unidades. No se
## asume ninguna orientacion ni escala: se mide la geometria real (vertices en
## espacio de bind llevados a modelo con la cadena hueso/bind) y se corrige el
## `ArmsMount` con esa medida. Asi los brazos quedan en metros y el ADS en
## centimetros, no en metros.
func _bind_vertices(arma_autor: MeshInstance3D) -> PackedVector3Array:
	var verts := PackedVector3Array()
	if arma_autor == null or arma_autor.mesh == null:
		return verts
	for si in range(arma_autor.mesh.get_surface_count()):
		var arrays := arma_autor.mesh.surface_get_arrays(si)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
	return verts


## Cadena del hueso del arma: bind -> espacio del modelo (arms_root).
func _bind_in_model(arma_autor: MeshInstance3D) -> Transform3D:
	var root_bone := arms_skeleton.find_bone(ARMS_WEAPON_BONE)
	if root_bone < 0:
		push_error("El rig no tiene hueso " + ARMS_WEAPON_BONE)
		return Transform3D.IDENTITY
	var root_name := arms_skeleton.get_bone_name(root_bone)
	var bind_index := -1
	for i in range(arma_autor.skin.get_bind_count()):
		if arma_autor.skin.get_bind_name(i) == root_name:
			bind_index = i
			break
	if bind_index < 0:
		push_error("Ningun bind del arma se llama " + root_name)
		return Transform3D.IDENTITY
	bind_in_skeleton = arms_skeleton.get_bone_global_rest(root_bone) * arma_autor.skin.get_bind_pose(bind_index)
	return _local_chain(arms_skeleton, arms_root) * bind_in_skeleton


## Transformacion local acumulada de `node` hasta su ancestro `ancestor`.
func _local_chain(node: Node, ancestor: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _bounds(verts: PackedVector3Array) -> AABB:
	if verts.is_empty():
		return AABB()
	var mn := verts[0]
	var mx := verts[0]
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	return AABB(mn, mx - mn)


## Caja envolvente de `box` expresada en otro sistema (sus 8 esquinas).
func _box_in_frame(box: AABB, t: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var mn := box.position
	var mx := box.position + box.size
	for xi in [0.0, 1.0]:
		for yi in [0.0, 1.0]:
			for zi in [0.0, 1.0]:
				var corner := Vector3(lerpf(mn.x, mx.x, xi), lerpf(mn.y, mx.y, yi), lerpf(mn.z, mx.z, zi))
				var p: Vector3 = t * corner
				if first:
					result = AABB(p, Vector3.ZERO)
					first = false
				else:
					result = result.expand(p)
	return result


func _centroid(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	return sum / float(maxi(points.size(), 1))


## Vertices de una primitiva concreta del arma del autor, en espacio de modelo.
func _surface_vertices(arma_autor: MeshInstance3D, surface_name: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if arma_autor == null or arma_autor.mesh == null or arms_skeleton == null or arma_autor.skin == null:
		return out
	var to_model := _bind_in_model(arma_autor)
	for i in range(arma_autor.mesh.get_surface_count()):
		if arma_autor.mesh.surface_get_name(i) != surface_name:
			continue
		var arrays := arma_autor.mesh.surface_get_arrays(i)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		for v in arrays[Mesh.ARRAY_VERTEX]:
			out.append(to_model * v)
	return out


## Mide la malla tal como viene del GLB: vertices en su espacio de bind, caja
## envolvente y marco real del arma. No se asume orientacion: el eje mas largo
## es el del canon, el mediano la altura y el mas corto la anchura. Los signos
## salen de la propia geometria (mira encima de la corredera, empunadura
## detras).
func _measure_mesh(arma_autor: MeshInstance3D) -> Dictionary:
	var result := {"ok": false}
	if arma_autor == null or arma_autor.mesh == null or arma_autor.skin == null or arms_skeleton == null:
		return result
	var bind_verts := _bind_vertices(arma_autor)
	if bind_verts.is_empty():
		return result
	var to_model := _bind_in_model(arma_autor)
	var verts := PackedVector3Array()
	verts.resize(bind_verts.size())
	for i in range(bind_verts.size()):
		verts[i] = to_model * bind_verts[i]
	var box := _bounds(verts)
	var size := box.size
	var axis_len := 0
	for i in range(1, 3):
		if size[i] > size[axis_len]:
			axis_len = i
	var axis := Vector3.ZERO
	axis[axis_len] = 1.0
	var helper := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x0 := helper.cross(axis).normalized()
	var y0 := axis.cross(x0).normalized()
	var base0 := Basis(x0, y0, axis)
	# Balanceo: el angulo que MINIMIZA el area de la seccion perpendicular al
	# canon. La seccion es alargada (alto contra ancho), asi que el minimo cae
	# en la orientacion alineada.
	var best_angle := 0.0
	var best_area := INF
	var best_lo := Vector2.ZERO
	var best_hi := Vector2.ZERO
	for step in range(0, 90):
		var angle := deg_to_rad(float(step))
		var probe := base0 * Basis(Vector3.BACK, angle)
		var inv := probe.inverse()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for v in verts:
			var local: Vector3 = inv * v
			lo.x = minf(lo.x, local.x)
			lo.y = minf(lo.y, local.y)
			hi.x = maxf(hi.x, local.x)
			hi.y = maxf(hi.y, local.y)
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		if area < best_area:
			best_area = area
			best_angle = angle
			best_lo = lo
			best_hi = hi
	var frame := base0 * Basis(Vector3.BACK, best_angle)
	if (best_hi.x - best_lo.x) > (best_hi.y - best_lo.y):
		frame = frame * Basis(Vector3.BACK, PI * 0.5)
	var to_frame := frame.inverse()
	var slide_mid: Vector3 = to_frame * _centroid(_surface_vertices(arma_autor, "Slide"))
	var sight_mid: Vector3 = to_frame * _centroid(_surface_vertices(arma_autor, "White"))
	var magazine_mid: Vector3 = to_frame * _centroid(_surface_vertices(arma_autor, "Magazine"))
	var up := frame.y
	var forward := frame.z
	if (sight_mid - slide_mid).y < 0.0:
		up = -up
	if (magazine_mid - slide_mid).z > 0.0:
		forward = -forward
	var right := up.cross(-forward).normalized()
	result["ok"] = true
	result["verts"] = verts
	result["frame"] = Basis(right, up, -forward)
	var final_inv: Basis = (result["frame"] as Basis).inverse()
	var f_lo := Vector3(INF, INF, INF)
	var f_hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		var local: Vector3 = final_inv * v
		f_lo = f_lo.min(local)
		f_hi = f_hi.max(local)
	result["frame_box"] = AABB(f_lo, f_hi - f_lo)
	result["length"] = maxf(size.x, maxf(size.y, size.z))
	return result


## Corrige el ArmsMount para que la malla quede en el marco del arma: -Z
## adelante (boca), +Y arriba (corredera) y +X derecha, con la escala real
## (Glock 19 = 186 mm de largo). La correccion sale de la cadena medida
## hueso/bind/armature, no de numeros fijos.
func _align_arms_with_mesh(measure: Dictionary, holder: Node3D) -> void:
	if holder == null or arms_skeleton == null:
		return
	gun_frame_bind = measure["frame"]
	var frame_box: AABB = measure["frame_box"]
	# Escala UNIFORME por el largo del canon: conserva todos los angulos del
	# rig (la no uniforme por ejes cizallaba el esqueleto y dejaba la pistola
	# vertical). Las proporciones reales del arma salen solas del GLB.
	var uni := GUN_LENGTH / maxf(frame_box.size.z, 0.000001)
	var axis_scale := Vector3(uni, uni, uni)
	holder.basis = Basis.IDENTITY.scaled(axis_scale) * gun_frame_bind.inverse()
	var centred := _box_in_frame(_bounds(measure["verts"]), holder.basis)
	# Ojo: la cadena incluye arms_root (identidad) y Armature (336x): al medir
	# la caja se usa solo el basis del holder porque la medida ya viene en
	# espacio de modelo (bind_in_model incluye la cadena hasta arms_root).
	var box_centre := centred.position + centred.size * 0.5
	holder.position = Vector3(
		-box_centre.x,
		GUN_TOP_OVER_ORIGIN - (centred.position.y + centred.size.y),
		-box_centre.z
	)
	print("RIG_MEDIDA escala_ejes=", axis_scale.snapped(Vector3(0.0001, 0.0001, 0.0001)),
		" anclaje=", holder.position.snapped(Vector3(0.0001, 0.0001, 0.0001)))


## Hueso de MANO del lado pedido ("l" o "r").
##
## El importador puede añadir un sufijo numerico a los nombres, asi que no se
## busca por nombre exacto: se puntua ("hand" sin dedos para no confundirla con
## un nudillo, lado por sufijo .l/.r).
func _find_hand_bone(lado: String) -> int:
	if arms_skeleton == null:
		return -1
	var best := -1
	var best_score := -1
	for i in range(arms_skeleton.get_bone_count()):
		var n := arms_skeleton.get_bone_name(i).to_lower()
		if not n.contains("hand"):
			continue
		if n.contains("finger") or n.contains("thumb") or n.contains("palm"):
			continue
		var es_lado := n.contains("." + lado) or n.contains("_" + lado) or n.contains("-" + lado)
		if not es_lado:
			continue
		var score := 1
		if n.contains("def"):
			score += 6
		if n.begins_with("def-hand"):
			score += 4
		if score > best_score:
			best = i
			best_score = score
	return best


# ---------------------------------------------------------------------------
# CARGADOR: socket en la mano
# ---------------------------------------------------------------------------
## Cuelga un punto del hueso de la mano izquierda. El offset real se mide en el
## primer agarre (ver Glock.gd), no se inventa aqui.
func _mount_hand_socket() -> void:
	_hand_bone = _find_hand_bone("l")
	if _hand_bone < 0:
		return
	hand_socket = BoneAttachment3D.new()
	hand_socket.name = "HandSocket"
	hand_socket.bone_idx = _hand_bone
	arms_skeleton.add_child(hand_socket)
	_apply_viewmodel_layer(hand_socket)


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
	# Conservar el global: el socket cuelga del esqueleto (otra escala) y con
	# keep=false el cargador heredaria su tamano multiplicado por ~4.
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
# Materiales y utilidades de malla
# ---------------------------------------------------------------------------
const FABRIC_SPECULAR := 0.22
## El key del viewmodel (2.9) quema el salvia del autor: se baja a 0.22
## (verificado en :0; a 0.5 sale casi blanco).
const ARMS_TAME := 0.22
const ARMS_ROUGHNESS := 0.95


func _darken_arms() -> void:
	_tame_mesh(arms_mesh_visible)
	_tame_mesh(arms_sleeve_visible)


## Deja la tela como tela: conserva el tono del autor (camisa oliva, piel,
## guante oscuro) pero anula el metalico que trae el GLB (0.4 hasta en la piel)
## y sube la rugosidad. Sin esto las manos salen espejadas o quemadas.
func _tame_mesh(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null:
		return
	for si in range(mi.mesh.get_surface_count()):
		var base: Material = mi.mesh.surface_get_material(si)
		if base is StandardMaterial3D:
			var src := base as StandardMaterial3D
			var fabric := src.duplicate() as StandardMaterial3D
			fabric.albedo_color = Color(src.albedo_color.r * ARMS_TAME,
				src.albedo_color.g * ARMS_TAME, src.albedo_color.b * ARMS_TAME, 1.0)
			fabric.metallic = 0.0
			fabric.metallic_specular = FABRIC_SPECULAR
			fabric.roughness = ARMS_ROUGHNESS
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


## Caja global que cubre todas las piezas de malla bajo un nodo.
func _caja_mundo(nodo: Node) -> AABB:
	var caja := AABB()
	var primero := true
	for m in _collect_meshes(nodo):
		var mundo: AABB = m.global_transform * m.mesh.get_aabb()
		caja = mundo if primero else caja.merge(mundo)
		primero = false
	return caja


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
	# Este rig no trae Fire: se mapea a su clip real. Reload e Inspect van a
	# Idle (sujecion): el gesto Reload del autor cruza el guante por el
	# objetivo un segundo entero y ninguna pose lo evita (verificado en
	# pantalla). El cargador sigue viajando mano<->brocal por los eventos
	# medidos de Glock.gd, con la red de tiempos como respaldo.
	var alias := short_name
	if short_name == "Fire":
		alias = "Shoot"
	elif short_name == "Reload_Empty" or short_name == "Reload":
		alias = "Idle"
	elif short_name == "Inspect":
		alias = "Idle"
	var resolved := _resolve_clip(alias)
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
	pos.x += _in_reload_pose * RELOAD_POSE_RIGHT
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
