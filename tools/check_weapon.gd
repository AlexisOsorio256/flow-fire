extends Node
## INVARIANTES DEL ARMA, sin abrir el editor ni mirar la pantalla.
##
##   godot --headless --path . tools/check_weapon.tscn
##
## Comprueba lo que el ojo no mide: el contrato del GLB (174 mm) separado de la
## referencia física publicada (185 mm), que existan las piezas que el juego mueve, que la
## boca de la malla caiga sobre la boca del cañon, que la corredera retroceda de
## verdad (alejandose de esa boca), que las miras esten en su orden y que al
## apuntar la linea de miras quede sobre el eje de la camara. Si algo falla,
## imprime FALLO y sale con codigo 1.

## Contratos independientes del runtime: si se cambia GlockWeapon para que el
## check se dé la razón a sí mismo, estas referencias siguen siendo las mismas.
const CANONICAL_MESH_LENGTH_M := 0.174
const REFERENCE_LENGTH_M := 0.185
const REFERENCE_TRIGGER_TRAVEL_M := 0.0125
const REFERENCE_SLIDE_TRAVEL_M := 0.039
const MAG_STANDARD := 15
const TOLERANCE := 0.002
## El rig del viewmodel: la sonda monta el mismo que el juego para medir el ADS.
const PLAYER := preload("res://scripts/Player.gd")


func _ready() -> void:
	var vm: Node3D = GlockViewmodel.new()
	add_child(vm)
	vm.mount()
	var weapon = vm.get("weapon")
	var failures := 0

	if weapon == null:
		print("FALLO: el arma no monto")
		get_tree().quit(1)
		return

	print("--- ARMA ---")
	print("escala del modelo ", snappedf(weapon.model_scale, 0.0001),
		"  capacidad ", weapon.capacity, " (std Gen5 15)")
	if weapon.capacity != MAG_STANDARD:
		failures += 1
		print("FALLO: capacidad no es el estandar Gen5 de 15")
	if weapon.muzzle != null and weapon.barrel != null and weapon.muzzle.get_parent() != weapon.barrel:
		failures += 1
		print("FALLO: Muzzle debe colgar de Barrel, no de Slide")
	if weapon.get("grip") == null or weapon.get("magwell") == null:
		failures += 1
		print("FALLO: faltan sockets canonicalizados Grip/Magwell")

	# El largo se mide DENTRO del arma (unidades del modelo) y se lleva al mundo
	# con la escala que el arma tiene de verdad: asi se caza cualquier escala
	# heredada de un padre (era el bug de los brazos a ARMS_SCALE).
	var world_scale: float = weapon.global_transform.basis.get_scale().x
	_local_aabb(weapon, true)
	var length: float = _local_length(weapon) * world_scale
	print("largo en el mundo mm ", snappedf(length * 1000.0, 0.1),
		"  (GLB canonico %.1f, ref %.1f, escala %.4f)" % [CANONICAL_MESH_LENGTH_M * 1000.0, REFERENCE_LENGTH_M * 1000.0, world_scale])
	if absf(length - CANONICAL_MESH_LENGTH_M) > TOLERANCE:
		failures += 1
		print("FALLO: el GLB canonico no conserva su longitud declarada")
	if not is_equal_approx(world_scale, 1.0):
		failures += 1
		print("FALLO: el runtime esta escalando la Glock")

	if weapon.muzzle == null or weapon.ejection_port == null \
			or weapon.sight_rear == null or weapon.sight_front == null \
			or weapon.frame == null or weapon.slide == null or weapon.magazine == null \
			or weapon.trigger == null or weapon.barrel == null \
			or weapon.grip == null or weapon.magwell == null:
		failures += 1
		print("FALLO: falta una pieza obligatoria o un punto del GLB canonico")
	print("piezas obligatorias: Frame/Slide/Barrel/Trigger/Magazine + Muzzle/EjectionPort/SightRear/SightFront/Grip/Magwell")
	# CONTRATO DE LOS BRAZOS. Un brazo que no aguanta una captura es peor que no
	# tener brazo, asi que el asset es obligatorio y se le exige lo que el runtime
	# da por hecho: los cinco clips con los nombres exactos que pide `Glock.gd`,
	# un esqueleto que solo deforma, y la raiz del brazo COINCIDIENDO con la del
	# arma (si no coincide, el encuadre se cae en la primera captura).
	if vm.get("arms_rig") == null:
		failures += 1
		print("FALLO: el viewmodel debe montar el asset de brazos")
	else:
		failures += _check_arms(vm)
	var weapon_meshes := _mesh_nodes(weapon)
	var weapon_tris := 0
	for mesh_instance: MeshInstance3D in weapon_meshes:
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var indices: PackedInt32Array = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			weapon_tris += indices.size() / 3
	print("arma sola: mallas=", weapon_meshes.size(), " triangulos=", weapon_tris)
	if weapon_meshes.is_empty() or weapon_tris < 3000:
		failures += 1
		print("FALLO: el arma debe traer su geometria (>=3k tris)")

	var sight_axis: Vector3 = (weapon.sight_front.global_position - weapon.sight_rear.global_position).normalized()
	var up: Vector3 = weapon.slide.global_transform.basis.y.normalized()
	var mag_axis: Vector3 = weapon.magazine_out_axis()
	print("mira trasera->delantera mm ",
		snappedf(weapon.sight_rear.global_position.distance_to(weapon.sight_front.global_position) * 1000.0, 0.1))
	## El sentido de la boca sale del CAÑON, que es geometria: la recamara esta en
	## el origen de la pieza y la boca en el CENTROIDE de su cara frontal (los
	## vertices a <2 mm de la profundidad maxima). El vertice mas lejano es una
	## esquina de la corona y esta a ~6 mm del anima: medir contra el obligaba a
	## descentrar la boca para pasar el check. La linea de miras no vale de
	## referencia: con las miras cambiadas de sitio, la comprobacion se daba la
	## razon a si misma (que es como el eje de la boca quedo al reves y el punto
	## de boca acabo en la culata, 166 mm del cañon).
	var bore_dir: Vector3 = sight_axis
	if weapon.barrel != null:
		var bore: Vector3 = _barrel_crown(weapon.barrel)
		bore_dir = (bore - weapon.barrel.global_transform.origin).normalized()
		print("mira trasera->delantera hacia la boca ", snappedf(sight_axis.dot(bore_dir), 0.01),
			"  (tiene que ser POSITIVO)")
		if sight_axis.dot(bore_dir) < 0.9:
			failures += 1
			print("FALLO: las miras estan cambiadas de sitio")
		if weapon.muzzle != null:
			var bore_mm: float = bore.distance_to(weapon.muzzle.global_position) * 1000.0
			print("punto de boca a la boca del cañon mm ", snappedf(bore_mm, 0.1))
			if bore_mm > 4.0:
				failures += 1
				print("FALLO: el punto de boca no esta en la boca del cañon")

	# La corredera RETROCEDE: tiene que alejarse de la boca al abrirse. Con el
	# eje de la boca invertido el arma recorria sus 39 mm hacia EL MORRO y se
	# veia abierta (la corredera salida del armazon por delante).
	weapon.set_slide(0.0)
	var slide_closed: Vector3 = weapon.slide.global_position
	weapon.set_slide(1.0)
	var slide_open: Vector3 = weapon.slide.global_position
	weapon.set_slide(0.0)
	var recoil_dir: Vector3 = (slide_open - slide_closed).normalized()
	print("la corredera al abrir va hacia la boca ", snappedf(recoil_dir.dot(bore_dir), 0.01),
		"  (tiene que ser NEGATIVO)")
	if recoil_dir.dot(bore_dir) > -0.9:
		failures += 1
		print("FALLO: la corredera no retrocede (va hacia la boca)")

	print("eje de salida del cargador ", mag_axis.snapped(Vector3(0.01, 0.01, 0.01)),
		"  abajo=", snappedf(mag_axis.dot(up), 0.01), "  avance=", snappedf(absf(mag_axis.dot(sight_axis)), 0.01))
	if mag_axis.dot(up) > -0.8 or absf(mag_axis.dot(sight_axis)) > 0.4:
		failures += 1
		print("FALLO: el cargador no sale hacia abajo por el brocal")

	# El gatillo gira sobre el pasador: si el eje estuviera mal, la punta se
	# moveria en diagonal o el pasador se iria de sitio.
	if weapon.trigger != null:
		var pivot: Vector3 = weapon.trigger.global_transform.origin
		## Se sigue el MISMO vertice en las dos poses. Buscar "el mas lejano"
		## cada vez no vale: la punta es un filo y el argmax salta de un vertice
		## a otro, que es como esta comprobacion midio 0,6 mm de 5 mm.
		var witness: Array = _witness_vertex(weapon.trigger)
		weapon.set_trigger(0.0)
		var tip_released := _witness_position(witness)
		weapon.set_trigger(1.0)
		var tip_pressed := _witness_position(witness)
		## Mundo ya viene en metros: no se vuelve a escalar.
		var trigger_travel: float = tip_released.distance_to(tip_pressed)
		var pin_shift: float = pivot.distance_to(weapon.trigger.global_transform.origin)
		print("gatillo mm ", snappedf(trigger_travel * 1000.0, 0.1),
			"  (recorrido Gen5 %.1f)  pasador movido mm %.2f" % [
				REFERENCE_TRIGGER_TRAVEL_M * 1000.0, pin_shift * 1000.0])
		if absf(trigger_travel - REFERENCE_TRIGGER_TRAVEL_M) > 0.0012 or pin_shift > 0.0002:
			failures += 1
			print("FALLO: el gatillo no gira sobre su pasador")
		weapon.set_trigger(0.0)

	# El cañon cae al abrirse el arma: si subiera, el giro esta al reves.
	if weapon.barrel != null:
		## Se mide la BOCA del cañon, no el nodo `Muzzle`: ese cuelga de la
		## corredera y se mueve con ella, asi que no dice nada del cañon.
		var muzzle_witness: Array = _witness_vertex(weapon.barrel)
		weapon.set_slide(0.0)
		var muzzle_closed := _witness_position(muzzle_witness)
		weapon.set_slide(1.0)
		var muzzle_open := _witness_position(muzzle_witness)
		weapon.set_slide(0.0)
		print("cañon al abrir mm ", snappedf((muzzle_closed - muzzle_open).dot(up) * 1000.0, 0.1),
			"  (baja si es positivo)")
		if (muzzle_closed - muzzle_open).dot(up) < 0.0005:
			failures += 1
			print("FALLO: el cañon no cae al abrir la corredera")

	# El gatillo NO puede salir con el cargador. Hasta ahora los dos vivian en el
	# mismo nodo del autor, asi que al expulsar el cargador se iba el gatillo.
	if weapon.trigger != null and weapon.magazine != null:
		var trigger_before: Vector3 = weapon.trigger.global_transform.origin
		weapon.set_magazine_offset(weapon.magazine_travel)
		var trigger_after: Vector3 = weapon.trigger.global_transform.origin
		weapon.set_magazine_offset(0.0)
		print("gatillo quieto con el cargador fuera mm ",
			snappedf(trigger_before.distance_to(trigger_after) * 1000.0, 2))
		if trigger_before.distance_to(trigger_after) > 0.0005:
			failures += 1
			print("FALLO: el gatillo se va con el cargador")

	var slide_travel: float = (weapon.slide_offset / weapon.model_scale) * world_scale
	print("recorrido de corredera mm ", snappedf(slide_travel * 1000.0, 0.1),
		"  (real %.1f)" % (REFERENCE_SLIDE_TRAVEL_M * 1000.0))
	if absf(slide_travel - REFERENCE_SLIDE_TRAVEL_M) > TOLERANCE * 0.5:
		failures += 1
		print("FALLO: la corredera no recorre la distancia real")

	# --- PUNTERIA: al apuntar, la linea de miras tiene que quedar sobre el eje de
	# la camara. Se monta el MISMO rig que el juego (Player.WEAPON_RIG_POS): el
	# encuadre del viewmodel es parte de lo que se mide. Con las miras cambiadas
	# el ADS giraba el arma media vuelta y la dejaba de perfil.
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 82.0
	cam.near = 0.04
	add_child(cam)
	cam.current = true
	var rig := Node3D.new()
	rig.name = "WeaponRig"
	rig.position = PLAYER.WEAPON_RIG_POS
	cam.add_child(rig)
	vm.get_parent().remove_child(vm)
	rig.add_child(vm)
	vm.setup(cam)
	vm.set_pose_inputs(1.0, 0.0, 0.0, Vector2.ZERO, Vector2.ZERO, 0.0)
	for _i in range(90):
		vm.update(1.0 / 60.0)
	vm.force_update_transform()
	cam.force_update_transform()
	var cam_fwd: Vector3 = -cam.global_transform.basis.z.normalized()
	var sight_aim: Vector3 = (weapon.sight_front.global_position - weapon.sight_rear.global_position).normalized()
	var muzzle_front: float = (cam.global_transform.affine_inverse() * weapon.muzzle.global_position).z
	print("ADS: linea de miras contra el eje de la camara ", snappedf(sight_aim.dot(cam_fwd), 0.0001),
		"  (1.0 = alineada)")
	print("ADS: la boca por delante de la camara m ", snappedf(-muzzle_front, 0.001), "  (positivo)")
	if sight_aim.dot(cam_fwd) < 0.999 or muzzle_front > -0.05:
		failures += 1
		print("FALLO: al apuntar el arma no queda alineada con la camara")

	if failures == 0:
		print("OK: invariantes del arma")
	else:
		print("FALLOS: ", failures)
	get_tree().quit(1 if failures > 0 else 0)


## CONTRATO DE LOS BRAZOS, medido sobre el asset montado.
##
##   - existe un Skeleton3D y no trae huesos de mas (el exportador no debe
##     arrastrar IK, constraints ni helpers: la complejidad de autoria se queda
##     en Blender);
##   - estan los cinco clips, con el nombre exacto que pide `Glock.gd`;
##   - cada clip dura lo que dura su hito mecanico, porque comparten reloj;
##   - la raiz del brazo coincide con la del arma (si no, el agarre se sale del
##     encuadre en la primera captura);
##   - el presupuesto de geometria es el del contrato de produccion.
func _check_arms(vm: Node3D) -> int:
	var bad := 0
	var rig: Node3D = vm.get("arms_rig")
	var player: AnimationPlayer = vm.get("arms_player")
	var skeleton: Skeleton3D = null
	var meshes: Array[MeshInstance3D] = []
	var stack: Array = [rig]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Skeleton3D and skeleton == null:
			skeleton = node as Skeleton3D
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			meshes.append(node as MeshInstance3D)
		for child in node.get_children():
			stack.append(child)
	var tris := 0
	for mesh_instance in meshes:
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var indices: PackedInt32Array = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			tris += indices.size() / 3
	if skeleton == null:
		bad += 1
		print("FALLO: los brazos no traen Skeleton3D")
	if meshes.size() > 2:
		bad += 1
		print("FALLO: los brazos traen ", meshes.size(), " mallas (contrato: 1-2)")
	if tris < 4000 or tris > 24000:
		bad += 1
		print("FALLO: los brazos estan fuera del presupuesto de triangulos: ", tris)
	var bones := 0 if skeleton == null else skeleton.get_bone_count()
	if bones < 30 or bones > 60:
		bad += 1
		print("FALLO: huesos de brazo fuera de contrato (30-60): ", bones)
	# Nombres que delatan autoria filtrada al runtime.
	if skeleton != null:
		for i in range(skeleton.get_bone_count()):
			var bone := skeleton.get_bone_name(i).to_lower()
			for marker in ["ik", "ctrl", "control", "helper", "target", "_end", "pole"]:
				if bone.contains(marker):
					bad += 1
					print("FALLO: hueso de autoria exportado: ", bone)
					break
	if player == null:
		bad += 1
		print("FALLO: los brazos no traen AnimationPlayer")
	else:
		var expected := {
			"Idle": 3.0, "Fire": 0.26, "Reload": 2.10,
			"ReloadEmpty": 2.35, "Inspect": 2.00,
		}
		for clip in expected:
			var found: String = vm.call("_clip_name", clip)
			if found == "":
				bad += 1
				print("FALLO: falta el clip ", clip)
				continue
			var anim := player.get_animation(found)
			var duration: float = anim.length if anim != null else 0.0
			var want: float = expected[clip]
			print("clip %-12s %.3f s (mecanica %.2f s) pistas=%d" % [
				clip, duration, want, 0 if anim == null else anim.get_track_count()])
			if absf(duration - want) > 0.08:
				bad += 1
				print("FALLO: ", clip, " no dura lo que su hito mecanico")
	# La raiz del brazo tiene que caer sobre la del arma: es lo que hace que
	# GRIP_POS/GRIP_ROT puedan ser cero.
	(vm as Node3D).force_update_transform()
	rig.force_update_transform()
	var weapon: GlockWeapon = vm.get("weapon")
	weapon.force_update_transform()
	var delta: float = rig.global_position.distance_to(weapon.global_position)
	print("brazo mallas=%d tris=%d huesos=%d  raiz/arma mm=%.2f" % [
		meshes.size(), tris, bones, delta * 1000.0])
	if delta > 0.002:
		bad += 1
		print("FALLO: la raiz del brazo no coincide con la del arma")
	return bad


## Vertice testigo de la pieza: el mas lejano a su origen (la punta del
## gatillo, la boca del cañon). Devuelve [malla, indice] para poder seguir ESE
## vertice en otra pose.
func _witness_vertex(part: Node3D) -> Array:
	var witness: Array = []
	var radio := 0.0
	var pivot: Vector3 = part.global_transform.origin
	var stack: Array = [part]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh_instance: MeshInstance3D = n as MeshInstance3D
			for s in range(mesh_instance.mesh.get_surface_count()):
				var vertices: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for i in range(vertices.size()):
					var d: float = (mesh_instance.global_transform * vertices[i]).distance_to(pivot)
					if d > radio:
						radio = d
						witness = [mesh_instance, i]
		for c in n.get_children():
			stack.append(c)
	return witness


func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			result.append(node as MeshInstance3D)
		for child in node.get_children():
			stack.append(child)
	return result


func _nodes_of_type(root: Node, type: Variant) -> Array:
	var result: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if is_instance_of(node, type):
			result.append(node)
		for child in node.get_children():
			stack.append(child)
	return result


func _contains_type(root: Node, type: Variant) -> bool:
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if is_instance_of(node, type):
			return true
		for child in node.get_children():
			stack.append(child)
	return false


## Centroide en mundo de la cara frontal del cañon: la corona donde termina el
## anima. Es el punto contra el que tiene que caer `Muzzle` (tolerancia 4 mm).
func _barrel_crown(part: Node3D) -> Vector3:
	var origin: Vector3 = part.global_transform.origin
	var rough: Vector3 = _witness_position(_witness_vertex(part)) - origin
	if rough.length() < 0.0001:
		return origin
	rough = rough.normalized()
	var verts: Array = []
	var stack: Array = [part]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh_instance: MeshInstance3D = n as MeshInstance3D
			for s in range(mesh_instance.mesh.get_surface_count()):
				var arrays: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in arrays:
					verts.append(mesh_instance.global_transform * v)
		for c in n.get_children():
			stack.append(c)
	if verts.is_empty():
		return origin
	var deepest := -1.0
	for v in verts:
		deepest = maxf(deepest, (v - origin).dot(rough))
	var center := Vector3.ZERO
	var count := 0
	for v in verts:
		if deepest - (v - origin).dot(rough) < 0.002:
			center += v
			count += 1
	if count == 0:
		return origin
	return center / float(count)


## Posicion en mundo del vertice testigo.
func _witness_position(witness: Array) -> Vector3:
	if witness.is_empty():
		return Vector3.ZERO
	var mesh_instance: MeshInstance3D = witness[0]
	var vertices: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return mesh_instance.global_transform * vertices[witness[1]]


## Largo de la pistola en unidades del PROPIO arma (sin rotaciones de padre).


func _local_length(root: Node3D) -> float:
	return maxf(_local_aabb(root, false).size.x, maxf(_local_aabb(root, false).size.y, _local_aabb(root, false).size.z))


## Caja del arma en su propio espacio. Con `detalle` imprime la caja de cada
## malla: si el largo sale mal, aqui se ve QUE pieza se esta saliendo.
func _local_aabb(root: Node3D, verbose: bool) -> AABB:
	var box := AABB()
	var first := true
	var inverse := root.global_transform.affine_inverse()
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local_box: AABB = (inverse * (n as Node3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
			if verbose:
				print("  pieza ", (n as Node3D).name, "  caja ",
					local_box.size.snapped(Vector3(0.001, 0.001, 0.001)),
					"  desde ", local_box.position.snapped(Vector3(0.001, 0.001, 0.001)))
			box = local_box if first else box.merge(local_box)
			first = false
		for c in n.get_children():
			stack.append(c)
	if verbose:
		print("  caja total ", box.size.snapped(Vector3(0.001, 0.001, 0.001)))
	return box
