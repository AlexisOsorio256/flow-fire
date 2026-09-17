class_name GlockViewmodel
extends Node3D

## Presentacion del arma: rig, huesos, ADS, animaciones humanas y materiales.
##
## NO tiene autoridad de gameplay. No posee municion, recamara, corredera ni
## recarga: recibe ese estado ya decidido por `Glock.gd` y lo REPRESENTA
## (`set_pose_inputs`, `apply_mechanics`). Una sola realidad: el estado
## mecanico lo decide Glock; este archivo lo dibuja.
##
## Cadena de nodos:
##   Viewmodel -> PoseRoot(pose/sway/bob) -> WristPivot(retroceso) ->
##   RecoilNode -> ArmsMount(escala) -> ArmsRoot(GLB) -> Skeleton3D
##   Skeleton3D -> SlideAttach -> SightRear/SightFront/Muzzle/EjectionPort
##
## El asset (`full9mm_2k.glb`, 1Matzh) trae brazos Y pistola ya agarrada y
## animada en un solo rig: no hay segunda arma, ni retargeting, ni IK.
##
## OWNERSHIP DEL RIG (una sola autoridad por pieza; lo aplica
## `_strip_mechanical_tracks` al cargar):
##   Humano / brazos ........... AnimationPlayer (Idle/Fire/Reload/Reload_Empty)
##   Arma root durante Fire .... GlockRecoil (procedural) sobre la pose neutra
##   Arma root durante reload .. AnimationPlayer
##   Corredera ................. Glock.gd (`slide_pos`, recorrido visual mapeado)
##   Gatillo ................... Glock.gd (`trigger_visual`)
##   Cargador durante Fire ..... rigido con el arma (GlockRecoil)
##   Cargador durante reload ... AnimationPlayer (gesto del clip)

## Ojo -> mira trasera en ADS. 0.54 m es la distancia a la que un tirador real
## tiene el alza del ojo sin tocar la escala de los brazos (atada a la
## empunadura del asset). Mas alla el alza trasera deja de leerse.
const ADS_SIGHT_DISTANCE := 0.54
## Pose de cadera (validada). El ADS sale SOLO del solver geometrico.
const HIP_POS := Vector3(0.0, 0.122, -0.34)
## Recorrido VISUAL de la corredera en el asset (33.6 mm): la logica integra los
## 39 mm reales de una G19 y el mapeo lineal reproduce el estado logico, no la
## pista animada.
const SLIDE_VISUAL_TRAVEL := 0.0336
## Pose de recarga: el tirador sube el arma y la gira para ver el brocal del
## cargador. Sin esto la empunadura queda bajo el borde de la pantalla y el
## cargador sale del encuadre sin verse nunca.
const RELOAD_POSE_UP := 0.075
const RELOAD_POSE_FWD := 0.045
const RELOAD_POSE_PITCH := 0.17
const RELOAD_POSE_ROLL := -0.30
## Geometria del arma MEDIDA EN ESTE ASSET (offsets en espacio local del
## hueso que la mueve): corredera
## 29.4 x 42.4 x 176.3 mm; linea de mira de radio 158.3 mm y 13.6 mm sobre la
## boca (una G19 real anda por 160 mm y ~13 mm); boca 2.7 mm por delante del
## frente de corredera; puerto en el lado derecho; el gatillo se tira 4.6 mm
## hacia atras.
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

var camera: Camera3D
var recoil: GlockRecoil  # estado del retroceso; lo aplica update()
var pose_root: Node3D
var wrist_pivot: Node3D
var recoil_node: Node3D
var muzzle: Node3D
var ejection_port: Node3D
var viewmodel_light: OmniLight3D

# Entradas de pose: las escribe Glock una vez por frame. NO son estado
# propio; si algo no llega, se queda en su ultimo valor, no evoluciona solo.
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
var ads_offset := Vector3(0.0, 0.15, -0.24)  # pose de ADS: la resuelve solve_ads()
var ads_rot := Vector3.ZERO  # giro de ADS resuelto junto al offset (radianes)
var ads_solved := false  # solve_ads ya corrio con el arma real montada
# Huesos mecanicos (autoridad de la logica) y sus reposos locales.
var slide_bone := -1
var trigger_bone := -1
var weapon_bone := -1
var mag_bone := -1
var slide_rest := Vector3.ZERO
var trigger_rest := Vector3.ZERO
# Reposo del arma y del cargador: sobre ellos se suma el retroceso (ver
# apply_mechanics). El cargador es hueso hermano del arma, no hijo.
var weapon_rest := Vector3.ZERO
var mag_rest := Vector3.ZERO
var slide_attach: BoneAttachment3D  # la mira/boca van con la corredera real


## Capa de render EXCLUSIVA del viewmodel. El rig de brazos se dibuja en ella y
## las luces del viewmodel solo la iluminan a ella (`light_cull_mask`): la
## pistola se lee igual de bien, pero el mundo no recibe NINGUNA luz constante
## del jugador (de lo contrario, acercarse a una pared la bañaba). La cámara las
## ve porque su `cull_mask` es el de defecto (capas 1..20).
const VIEWMODEL_LAYER := 13
const VIEWMODEL_LAYER_BIT := 1 << (VIEWMODEL_LAYER - 1)

## Luces del viewmodel: con su albedo real (polímero ~0.08) el arma se leía como
## una mancha negra. Dos luces cortas y sin sombras (clave arriba-izquierda y
## relleno desde la cámara) la definen. Cuelgan de pose_root para que acompañen
## al arma en recarga y apuntado.
##
## AÍSLAN su influencia, no se apagan: `light_cull_mask` las limita a
## VIEWMODEL_LAYER, así que mundo y viewmodel viven en dos regímenes de luz
## separados (el fogonazo es la única luz del arma que toca el mundo, y solo
## durante el disparo).
func _build_viewmodel_light() -> void:
	viewmodel_light = OmniLight3D.new()
	viewmodel_light.name = "ViewmodelKey"
	viewmodel_light.light_color = Color(0.94, 0.96, 1.0)
	viewmodel_light.light_energy = 2.9
	viewmodel_light.omni_range = 1.5
	viewmodel_light.omni_attenuation = 1.35
	viewmodel_light.shadow_enabled = false
	viewmodel_light.light_cull_mask = VIEWMODEL_LAYER_BIT
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
	fill.light_cull_mask = VIEWMODEL_LAYER_BIT
	fill.position = Vector3(0.28, -0.08, 0.46)
	pose_root.add_child(fill)


## El viewmodel entero (mallas y huesos) vive en VIEWMODEL_LAYER: las luces del
## viewmodel iluminan esa capa y las del mundo (sun y lámparas, cull_mask por
## defecto = todas las capas) NO, así que el arma no recibe la luz de la sala ni
## devuelve ninguna. Un VisualInstance3D sin `layers` explícitos (el caso del GLB
## importado) usa el valor por defecto, así que hay que escribirlo a mano.
func _apply_viewmodel_layer(root_node: Node) -> void:
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = VIEWMODEL_LAYER_BIT
		for c in n.get_children():
			stack.append(c)


func _build_viewmodel() -> void:
	# El arma visible es la del asset de primera persona: aqui solo se prepara
	# su marco. La mira, la boca y el fogonazo (que si son de FlowFire) se
	# montan sobre la corredera real en _install_arms.
	_build_high_fidelity_pistol()
	print("GLOCK arma=asset 9mm 1Matzh")


## Pose del rig: cadera/sprint/ADS + balanceo, bob, respiracion y pose de
## recarga. El apuntado ya viene suavizado desde Glock.
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

	pos += recoil.arm_pos
	rot += recoil.arm_rot
	rot.x += sway.y * 0.5 + sin(idle_phase * 1.05) * 0.0025 * (1.0 - _in_aim * 0.6) - move_y * 0.008
	rot.y += sway.x * 0.5 + sin(idle_phase * 0.73 + 1.0) * 0.0020 * (1.0 - _in_aim * 0.6)
	rot.z += -move_x * 0.012 - sin(bob_phase) * 0.012 * _in_sprint
	# El tope tiene que dejar pasar la pose de ADS: la pistola sube desde la
	# postura baja de descanso hasta la mira sin quedar recortada.
	# El limite sigue existiendo para el balanceo, el bob y el retroceso, que son
	# los que podian desmadrar el arma.
	pos.x = clampf(pos.x, -0.30, 0.30)
	pos.y = clampf(pos.y, -0.30, maxf(0.18, ads_pos.y))
	pos.z = clampf(pos.z, minf(-0.45, ads_pos.z), 0.15)
	# El límite del balanceo no debe recortar la inclinación que el solver de ADS
	# haya resuelto: la pose de apuntado puede necesitar más de 20° para que el
	# cañón quede apenas por debajo del frente. Hip y retroceso conservan el
	# límite corto.
	var rot_limit := maxf(0.35, absf(ads_pose_rot.x) + 0.015)
	rot.x = clampf(rot.x, -rot_limit, rot_limit)
	rot.y = clampf(rot.y, -0.35, 0.35)
	rot.z = clampf(rot.z, -0.25, 0.25)

	# Pose de recarga: sube y gira el arma para que el brocal entre en pantalla.
	# Las manos van en el mismo rig, así que suben con ella: no hay desincronía.
	pos.y += _in_reload_pose * RELOAD_POSE_UP
	pos.z += _in_reload_pose * RELOAD_POSE_FWD
	rot.x += _in_reload_pose * RELOAD_POSE_PITCH
	rot.z += _in_reload_pose * RELOAD_POSE_ROLL
	pose_root.position = pos
	pose_root.rotation = rot


func solve_ads() -> void:
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
	# del nodo: el Idle del asset sostiene la pistola con ~16 grados de canto y
	# nivelar el nodo deja la corredera torcida en ADS. La referencia es el arma.
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
# Escala uniforme del conjunto (manos + arma, un solo rig). CALIBRADA para el
# encuadre: el asset esta modelado ~1:1 en metros (corredera 29.4 mm como una
# real), asi que tambien agranda las manos; el encuadre y el ADS estan validados
# sobre ella.
const ARMS_SCALE := 1.362
# Punto de la empunadura en espacio de recoil que fija el encuadre de cadera
# validado, y distancia hueso-arma -> punto de referencia hacia la boca.
# Son el ancla del montaje, no geometria medida: el ADS los ignora (lo resuelve
# solve_ads desde la mira real).
const GRIP_ANCHOR := Vector3(0.0, -0.088, 0.038)
const GRIP_AHEAD := 0.080

var arms_mount: Node3D  # soporte estatico bajo RecoilNode (escala uniforme)
var arms_root: Node3D
var arms_skeleton: Skeleton3D
var arms_player: AnimationPlayer
var arms_mesh_visible: MeshInstance3D  # malla de manos (la matiza _darken_arms)
var arms_sleeve_visible: MeshInstance3D  # antebrazos/mangas (idem)
var arms_ok := false


## ---------------------------------------------------------------------------
## Arma de alta fidelidad: la del propio asset, sin piezas paralelas.
##
## Aqui solo se crea el marco (GunFrame, referencia espacial bajo el retroceso).
## La mira trasera/delantera, la boca y el puerto cuelgan de la CORREDERA REAL
## (hueso Slidder_919) via BoneAttachment3D en _install_arms: se mueven con la
## animacion y con la logica porque SON el arma, no una copia. El fogonazo lo
## cuelga Glock de esa boca (ver WeaponFX.gd).
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
	# Aísla el rig en su capa: ni las luces del mundo lo alcanzan ni las suyas
	# tocan el mundo (ver _apply_viewmodel_layer).
	_apply_viewmodel_layer(arms_root)

	# TODAS las mallas se dibujan: este rig trae brazos Y arma ya montada y
	# animada. Solo se apaga el skybox de presentacion (AABB 2x2) y los
	# ayudantes de apuntado, que no son personaje.
	var meshes := _collect_meshes(arms_root)
	var hidden := 0
	var arms_best: MeshInstance3D = null
	var arms_most := -1
	for m in meshes:
		var sz := (m.mesh as Mesh).get_aabb().size
		var tris := 0
		if m.mesh is ArrayMesh:
			for si in range(m.mesh.get_surface_count()):
				var ar: Array = m.mesh.surface_get_arrays(si)
				if ar.size() > 0 and ar[Mesh.ARRAY_INDEX] != null:
					tris += (ar[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		# Skybox de presentacion (AABB 2x2) y ayudantes de apuntado (4 caras): no
		# son personaje. La pistola del asset SI se dibuja: es el arma de FlowFire.
		# Se reconoce por el HUESO que la mueve, no por el nombre de la malla (el
		# importador lo renombra).
		if (sz.x > 1.5 and sz.z > 1.5) or tris <= 16:
			m.visible = false
			hidden += 1
			continue
		# La malla de BRAZOS es la que deforman huesos de mano o antebrazo: elegir
		# la de mas vertices daria una malla que no son los brazos.
		var dom := _dominant_bone(m)
		if (dom.findn("hand") >= 0 or dom.findn("forearm") >= 0 or dom.findn("arm") >= 0) and _mesh_vert_count(m) > arms_most:
			arms_most = _mesh_vert_count(m)
			arms_best = m
	arms_mesh_visible = arms_best
	# Mangas: la otra malla de brazos (antebrazos), para matizar su tela.
	for m in meshes:
		if m.visible and m != arms_best:
			var dom2 := _dominant_bone(m)
			if dom2.findn("forearm") >= 0 or dom2.findn("arm") >= 0:
				arms_sleeve_visible = m
				break
	print("ARMS_MALLAS total=", meshes.size(), " ocultas=", hidden,
		" brazos=", arms_best.name if arms_best else "NINGUNA",
		" verts=", arms_most)

	park_anim("Idle", 0.0)
	var weapon_idx := _exact_bone(WEAPON_BONE)
	var barrel_bone := _exact_bone(BARREL_BONE)
	var mag_idx := _exact_bone(MAG_BONE)
	slide_bone = _exact_bone(SLIDE_BONE)
	trigger_bone = _exact_bone(TRIGGER_BONE)
	weapon_bone = weapon_idx
	mag_bone = mag_idx
	if weapon_idx < 0 or barrel_bone < 0 or mag_idx < 0 or slide_bone < 0 or trigger_bone < 0:
		push_warning("El rig no trae los huesos del arma (Weapon/Barrel/Magazine/Slidder/Trigger)")
		holder.queue_free(); arms_root = null; return
	# El modelo apunta a +Z y la camara mira a -Z: giro 180 en Y. Asi el alza
	# delantera queda al fondo y la trasera cerca, como en su propia vista FPS.
	# La posicion lleva el punto de referencia de la empunadura al ancla: es lo
	# unico que fija el encuadre de cadera (residuo 0 por construccion).
	var scaled_r := Basis(Vector3.UP, PI).scaled(Vector3(ARMS_SCALE, ARMS_SCALE, ARMS_SCALE))
	var weapon_in_skel := arms_skeleton.get_bone_global_pose(weapon_bone).origin
	var barrel_in_skel := arms_skeleton.get_bone_global_pose(barrel_bone).origin
	var grip_ref: Vector3 = weapon_in_skel + (barrel_in_skel - weapon_in_skel).normalized() * GRIP_AHEAD
	holder.transform = Transform3D(scaled_r, GRIP_ANCHOR - scaled_r * grip_ref)
	var grip_err: float = (holder.transform * grip_ref - GRIP_ANCHOR).length() * 1000.0
	print("ARMS_MONTAJE escala=", snappedf(ARMS_SCALE, 0.0001),
		" residuo_empunadura_mm=", snappedf(grip_err, 0.1))
	# Reposos mecanicos: la pose local sin animar de corredera, gatillo, arma y
	# cargador. El arma y el cargador son la base sobre la que se suma el
	# retroceso (apply_mechanics).
	slide_rest = arms_skeleton.get_bone_rest(slide_bone).origin
	trigger_rest = arms_skeleton.get_bone_rest(trigger_bone).origin
	weapon_rest = arms_skeleton.get_bone_rest(weapon_bone).origin
	mag_rest = arms_skeleton.get_bone_rest(mag_bone).origin
	_mount_slide_attachments()
	_strip_mechanical_tracks()
	_measure_wrist(weapon_bone)
	# La pistola visible es la del propio asset y ya viene montada y animada en
	# su esqueleto, asi que no hay segunda arma que colgar.
	_darken_arms()
	arms_ok = true
	pistol_ok = true
	play_anim("Idle", true)
	print("ARMS_1MATZH ok manos_mandan anim=", arms_player.get_animation_list())
	if camera != null and not ads_solved:
		solve_ads()


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
	# Los ayudantes de la boca (fogonazo y su luz) también son viewmodel.
	_apply_viewmodel_layer(att)
	print("ARMS_MIRA corredera_real lista")


func _attach_point(parent: Node3D, point_name: String, offset: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = point_name
	parent.add_child(n)
	n.position = offset
	return n


## Aplica el OWNERSHIP del rig (ver cabecera) a los tres clips que la logica
## controla, quitando de cada uno las pistas que no le pertenecen. Explicito a
## proposito: al leerlo se ve que manda cada capa.
func _strip_mechanical_tracks() -> void:
	var idle_weapon: Variant = _sample_bone_position("Idle", WEAPON_BONE)

	# FIRE: la animacion manda en el humano; la logica en corredera y gatillo;
	# GlockRecoil en la ROTACION del arma; el cargador va rigido con el arma.
	# La POSICION del arma NO se borra: se clona la de Idle, porque el clip Fire
	# la hunde y el reposo no es la pose montada (se veria el arma delante y el
	# cargador en la mano).
	var fire := _resolve_clip("Fire")
	if fire != "":
		if idle_weapon != null:
			_set_bone_position(fire, WEAPON_BONE, idle_weapon)
		_remove_bone_rotation(fire, WEAPON_BONE)
		_remove_bone_tracks(fire, MAG_BONE)
		_remove_bone_tracks(fire, SLIDE_BONE)
		_remove_bone_tracks(fire, TRIGGER_BONE)
		print("ARMS_PISTA ", fire, " neutralizada")

	# RELOAD / RELOAD_EMPTY: el gesto de sacar y meter el cargador, y la posicion
	# del arma, son de la animacion. La logica solo manda en corredera y gatillo.
	for clip_name in ["Reload", "Reload_Empty"]:
		var clip := _resolve_clip(clip_name)
		if clip != "":
			_remove_bone_tracks(clip, SLIDE_BONE)
			_remove_bone_tracks(clip, TRIGGER_BONE)


## Nombre real de un clip en el AnimationPlayer (el importador puede prefijarlo).
func _resolve_clip(short_name: String) -> String:
	if arms_player == null:
		return ""
	for candidate in arms_player.get_animation_list():
		if candidate == short_name or candidate.ends_with("|" + short_name):
			return candidate
	return ""


## Borra de un clip toda pista (posicion/rotacion/escala) de un hueso.
func _remove_bone_tracks(resolved: String, bone: String) -> void:
	var anim: Animation = arms_player.get_animation(resolved)
	for ti in range(anim.get_track_count() - 1, -1, -1):
		if str(anim.track_get_path(ti)).contains(":" + bone):
			anim.remove_track(ti)


## Borra solo la ROTACION de un hueso: su posicion la fija la logica por otra via.
func _remove_bone_rotation(resolved: String, bone: String) -> void:
	var anim: Animation = arms_player.get_animation(resolved)
	for ti in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(ti) == Animation.TYPE_ROTATION_3D and str(anim.track_get_path(ti)).contains(":" + bone):
			anim.remove_track(ti)


## Copia `value` en todas las claves de la pista de POSICION de un hueso.
func _set_bone_position(resolved: String, bone: String, value: Vector3) -> void:
	var anim: Animation = arms_player.get_animation(resolved)
	for ti in range(anim.get_track_count()):
		if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D and str(anim.track_get_path(ti)).contains(":" + bone):
			for k in range(anim.track_get_key_count(ti)):
				anim.track_set_key_value(ti, k, value)
			return


## Valor de la posicion de un hueso en un instante de un clip, para poder
## clonarlo o consultarlo sin duplicar la animacion.
func _sample_bone_position(short_name: String, bone: String) -> Variant:
	var resolved := _resolve_clip(short_name)
	if resolved == "":
		return null
	arms_player.play(resolved, -1.0, 1.0)
	arms_player.seek(0.0, true)
	arms_skeleton.force_update_all_bone_transforms()
	var idx := _exact_bone(bone)
	if idx < 0:
		return null
	return arms_skeleton.get_bone_pose_position(idx)


## Pivote del retroceso procedural: punto del agarre que sostiene el arma (35%
## del hueso del arma hacia el hueso de la mano), en el frame del ESQUELETO, que
## es donde el viewmodel escribe el hueso del arma.
func _measure_wrist(weapon_bone: int) -> void:
	var hand := _exact_bone("DEF-hand.R_842")
	if hand < 0:
		return
	arms_skeleton.force_update_all_bone_transforms()
	var weapon_p: Vector3 = arms_skeleton.get_bone_global_pose(weapon_bone).origin
	var hand_p: Vector3 = arms_skeleton.get_bone_global_pose(hand).origin
	var pivot := weapon_p + (hand_p - weapon_p) * 0.35
	if recoil != null:
		recoil.set_wrist_pivot(pivot)
	print("ARMS_MUNECA pivote=", pivot.snapped(Vector3(0.001, 0.001, 0.001)))


## Deja una animacion de brazos aparcada en un instante exacto.
func park_anim(short_name: String, t: float) -> bool:
	var resolved := _resolve_clip(short_name)
	if resolved == "":
		return false
	arms_player.play(resolved)
	arms_player.seek(t, true)
	arms_skeleton.force_update_all_bone_transforms()
	return true


## Guantes y mangas como TELA/CUERO, conservando las texturas del autor.
##
## El asset trae difusas reales (costuras, nudillos, tejido) y una textura ORM
## donde el canal metalico del guante esta a 0.99, con lo que el material sale
## cromado. La tela y el cuero son dielectricos, asi que el cambio minimo es:
## se tine el albedo (multiplica la difusa; el detalle sigue) y se fuerza un
## DIELECTRICO con specular bajo y el emisivo del autor apagado.
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
			print(label, " -> dielectrico rough=", roughness, " tinte=", tint)


func play_anim(short_name: String, loop := false) -> bool:
	if not arms_ok or arms_player == null:
		return false
	var resolved := _resolve_clip(short_name)
	if resolved == "":
		return false
	arms_player.play(resolved, -1.0, 1.0)
	if not loop:
		var idle := resolve_idle()
		if idle != "":
			arms_player.queue(idle)
	return true


func resolve_idle() -> String:
	return _resolve_clip("Idle")


## Escribe en los huesos el estado mecanico que le pasa Glock. Es el unico
## punto donde la logica toca el esqueleto: una sola realidad, representada.
##
## El ARMA retrocede AQUI, en su hueso, y no en los nodos del rig: la mano se
## queda donde la animacion la pone y el arma gira sobre el pivote del agarre y
## se hunde dentro de ella, que es lo que hace un retroceso real. (Rotar el
## viewmodel entero empujaria las manos hacia atras con el arma.)
##
## El CARGADOR recibe el mismo offset porque es un hueso hermano (cuelga de la
## raiz, no del arma): en Fire va rigido en el brocal y se mueve exactamente
## igual que el arma.
##
## Escribir a mano en el hueso sobrevive al AnimationPlayer mientras corre el
## clip; es lo que hace compatible la autoridad procedural con la animada.
func apply_mechanics(slide_pos: float, slide_travel: float, trigger_visual: float) -> void:
	if not pistol_ok or arms_skeleton == null or slide_bone < 0:
		return
	var ratio := SLIDE_VISUAL_TRAVEL / maxf(slide_travel, 0.0001)
	arms_skeleton.set_bone_pose_position(slide_bone, slide_rest + Vector3(0.0, 0.0, -slide_pos * ratio))
	if trigger_bone >= 0:
		arms_skeleton.set_bone_pose_position(trigger_bone, trigger_rest + TRIGGER_PULL * trigger_visual)
	if recoil != null:
		var kick := recoil.bone_offset(recoil.rot, weapon_rest)
		arms_skeleton.set_bone_pose_position(weapon_bone, weapon_rest + kick)
		arms_skeleton.set_bone_pose_position(mag_bone, mag_rest + kick)
	# En recarga el cargador lo lleva la mano en la animacion, en fase con ella
	# por construccion; aqui solo se le suma el retroceso.


## Cadena de nodos del rig. Se crea aqui y no en Glock: es presentacion.
func _ready() -> void:
	pose_root = Node3D.new()
	pose_root.name = "PoseRoot"
	add_child(pose_root)
	wrist_pivot = Node3D.new()
	wrist_pivot.name = "WristPivot"
	pose_root.add_child(wrist_pivot)
	recoil_node = Node3D.new()
	recoil_node.name = "RecoilNode"
	wrist_pivot.add_child(recoil_node)
	_build_viewmodel_light()


## Estado de pose del frame (lo llama Glock despues de actualizar la mecanica
## y el retroceso).
func set_pose_inputs(aim: float, sprint: float, speed: float, look: Vector2, move: Vector2, reload_pose: float) -> void:
	_in_aim = aim
	_in_sprint = sprint
	_in_speed = speed
	_in_look = look
	_in_move = move
	_in_reload_pose = reload_pose


func update(delta: float) -> void:
	_apply_pose(delta)
	if recoil != null:
		recoil.apply(wrist_pivot, recoil_node)


## ADS geometrico: alinea la linea de mira real con el eje de camara. Se
## resuelve una sola vez, despues de montar el arma y con la camara lista.
func setup(cam: Camera3D) -> void:
	camera = cam
	if arms_ok and not ads_solved:
		solve_ads()


## Monta el rig completo: nodos, arma del asset y brazos animados.
func mount() -> void:
	_build_viewmodel()
	_install_arms()


func play_fire() -> void:
	play_anim("Fire")


func play_reload(empty: bool) -> void:
	play_anim("Reload_Empty" if empty else "Reload")


func blend_to_idle(blend: float) -> void:
	if arms_player == null:
		return
	var idle := resolve_idle()
	if idle != "":
		arms_player.play(idle, blend)
