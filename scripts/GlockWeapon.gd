class_name GlockWeapon
extends Node3D

## EL ARMA: la Glock 19 en piezas rigidas, sin esqueleto y sin tabla.
##
## ARMA DE REFERENCIA: Glock 19 Gen5 stock, 9x19. Ficha congelada:
##   largo total 185 mm, cañon 102 mm, alto 128 mm, ancho 30 mm,
##   cargador estandar 15 cartuchos, recorrido de disparador ~12,5 mm (manual),
##   recorrido de corredera 39 mm (medido en el mundo).
## El .glb actual (Rotuma) mide 174 mm de largo: es APROXIMACION VISUAL, 11 mm
## corto frente a la ficha. Se dibuja a la medida de su malla y no se estira.
##
## El .glb del arma trae las piezas como nodos, cada una con su PROPIO origen:
##
##   Frame      armazon. Es el origen del arma y no lo mueve nadie.
##   Slide      corredera            <- set_slide(0..1)       (Glock.gd)
##   Magazine   cargador             <- set_magazine_offset   (Glock.gd)
##   Trigger    gatillo              <- set_trigger(0..1)     (Glock.gd)
##   Barrel     cañon + Muzzle + cartucho visible  <- cae con la corredera (set_slide)
##   EjectionPort / SightRear / SightFront / Grip / Magwell
##              sockets REALES dentro del GLB (canonicalizado en Blender:
##              Muzzle en la boca del canon a 0,0 mm, miras sobre la corredera,
##              Grip en el centroide de la empunadura, Magwell en la boca del
##              cargador). Los sockets no se buscan por AABB; la AABB total sólo
##              valida la longitud declarada del asset.
##
## Muzzle cuelga de Barrel en el GLB: el fogonazo no viaja con la corredera.
## Esa relacion forma parte del contrato del asset; el runtime no la repara.
##
## AQUI NO HAY GAMEPLAY: la autoridad de cada pieza es `Glock.gd`, y este archivo
## solo la representa. Los unicos numeros que viven aqui son los del arma fisica.
##
##   "la corredera no llega" -> SLIDE_TRAVEL
##   "el arma esta mal encuadrada" -> GlockViewmodel.GRIP_POS / GRIP_ROT

const MODEL := "res://assets/models/g19_pistol.glb"
## Mapas del arma. El .glb NO lleva texturas dentro: son estos PNG del repo, y
## son los MISMOS byte a byte que el .glb embebia. Se sacaron porque embebidos
## pesaban 10.186.698 bytes (el .glb entero pasaba de 10,05 MB) y aqui ya
## estaban: era la misma imagen dos veces en el repositorio.
##
## Los cuatro se cargan SOLO como imagen de GPU. En disco el normal map de
## 2048 px pesa 5 MB, pero en VRAM es la misma textura: por eso la duplicacion
## costaba espacio de repositorio y de import, no memoria de video.
const MAP_BASE_COLOR := "res://assets/models/g19_pistol_Image_3.png"
## Mapa empaquetado metallic-roughness (verde = rugosidad, azul = metalico),
## que es la convencion glTF. El shader `glock_pbr.gdshader` lee los canales
## correctos; StandardMaterial3D no deja elegir canal y por eso hay shader.
const MAP_SLIDE := "res://assets/models/g19_pistol_Image_4.png"
const MAP_EMISSIVE := "res://assets/models/g19_pistol_Image_5.png"
const MAP_NORMAL := "res://assets/models/g19_pistol_Image_6.png"
## Largo de la MALLA actual, extremo a extremo (174 mm medidos). No es la ficha:
## la Gen5 real mide 185 mm. El GLB canonico llega ya en metros; Godot solo
## VALIDA, no corrige en silencio (avisa si la escala se desvia >3%).
const ASSET_LENGTH_M := 0.174
## Recorrido real de la corredera. Es la unica autoridad del recorrido: la
## mecanica de Glock.gd y el dibujo la leen de aqui.
const SLIDE_TRAVEL := 0.039
## Cartuchos del cargador ESTANDAR de G19 Gen5: 15. Los de 17 son extendidos.
const MAG_CAPACITY := 15
## Hacia donde mira la boca de la malla, en el espacio del arma. En este asset
## el morro esta a -Z, el mismo eje que mira la camara: lo dice la propia malla
## (el cañon va delante del gatillo y el cargador detras de los dos) y lo mide
## `tools/check_weapon.gd` sobre la boca del cañon, no sobre el nodo `Muzzle`.
## La corredera retrocede al reves de la boca: con el signo cambiado recorria sus
## 39 mm HACIA EL MORRO y el arma se veia abierta por delante.
const MUZZLE_AXIS := Vector3(0.0, 0.0, -1.0)
## Recorrido real del cargador fuera del brocal, de asentado a libre.
const MAG_TRAVEL := 0.07
## Eje de salida del cargador en espacio del arma (abajo del armazon).
const MAGAZINE_OUT_AXIS := Vector3(0.0, -1.0, 0.0)
## Recorrido real del disparador Gen5, medido en la punta: ~12,5 mm (manual).
const TRIGGER_TRAVEL := 0.0125
## Cuanto baja el cañon cuando la corredera esta atras del todo. El bloqueo lo
## suelta el armazon y la recamara cae; son ~1,5 grados sobre la cara de culata.
const BARREL_DROP := 0.026
## Tramo inicial en que cañon y corredera retroceden JUNTOS antes del desbloqueo.
const BARREL_LOCK_TRAVEL := 0.004
## Eje lateral del arma en el espacio de su padre. El gatillo gira sobre el
## pasador y el cañon cae sobre este eje, NO sobre los ejes locales de cada
## pieza: las dos traen su propio origen y su propio giro.
const SIDE_AXIS := Vector3(1.0, 0.0, 0.0)

var slide_offset := SLIDE_TRAVEL
## Recorrido del cargador desde asentado hasta libre. Espejo de MAG_TRAVEL.
var magazine_travel := MAG_TRAVEL
var capacity := MAG_CAPACITY
var muzzle_axis := MUZZLE_AXIS
var model_scale := 1.0

var frame: Node3D
var slide: Node3D
var trigger: Node3D
var magazine: Node3D
var barrel: Node3D
var muzzle: Node3D
var ejection_port: Node3D
var sight_rear: Node3D
var sight_front: Node3D
var grip: Node3D
var magwell: Node3D

var _slide_rest := Vector3.ZERO
var _barrel_rest := Vector3.ZERO
## Cartucho en recamara, hijo de Barrel (cae con el cañon). Solo representacion:
## Glock.gd decide si hay cartucho (`chamber`) y si el puerto esta abierto.
var cartridge: Node3D
## Base local de cada pieza que gira: se multiplica por el giro del frame del
## padre, asi no importa como venga orientada la pieza en el archivo.
var _trigger_rest_basis := Basis.IDENTITY
var _trigger_lever := 0.0
var _barrel_rest_basis := Basis.IDENTITY
## Recorrido de la corredera en unidades del modelo (metros reales / escala).
var _slide_travel := 0.0
## Sitio exacto del cargador dentro del arma. Lo usa el viewmodel para
## devolverlo al brocal cuando la mano lo suelta.
var magazine_rest := Vector3.ZERO
var _magazine_rest_basis := Basis()


func build() -> bool:
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("No se pudo cargar el GLB canonico: " + MODEL)
		return false
	var root := packed.instantiate()
	add_child(root)

	frame = _find_child(root, "Frame")
	slide = _find_child(root, "Slide")
	magazine = _find_child(root, "Magazine")
	trigger = _find_child(root, "Trigger")
	barrel = _find_child(root, "Barrel")
	muzzle = _find_child(root, "Muzzle")
	ejection_port = _find_child(root, "EjectionPort")
	sight_rear = _find_child(root, "SightRear")
	sight_front = _find_child(root, "SightFront")
	grip = _find_child(root, "Grip")
	magwell = _find_child(root, "Magwell")
	var missing: Array[String] = []
	for pair in [["Frame", frame], ["Slide", slide], ["Barrel", barrel], ["Trigger", trigger],
			["Magazine", magazine], ["Muzzle", muzzle], ["EjectionPort", ejection_port],
			["SightRear", sight_rear], ["SightFront", sight_front], ["Grip", grip], ["Magwell", magwell]]:
		if pair[1] == null:
			missing.append(pair[0])
	if not missing.is_empty():
		push_error("GLB de Glock roto: faltan piezas obligatorias " + ", ".join(missing))
		return false
	if muzzle.get_parent() != barrel:
		push_error("GLB de Glock roto: Muzzle debe colgar de Barrel")
		return false
	if grip.get_parent() != frame or magwell.get_parent() != frame:
		push_error("GLB de Glock roto: Grip y Magwell deben colgar de Frame")
		return false
	if ejection_port.get_parent() != slide or sight_rear.get_parent() != slide or sight_front.get_parent() != slide:
		push_error("GLB de Glock roto: puerto y miras deben colgar de Slide")
		return false

	_slide_rest = slide.position
	_barrel_rest = barrel.position
	magazine_rest = magazine.position
	_magazine_rest_basis = magazine.transform.basis
	_trigger_rest_basis = trigger.transform.basis
	_barrel_rest_basis = barrel.transform.basis

	# El GLB canonico llega en metros: Godot solo VALIDA, nunca corrige. Fuera
	# del contrato es un asset roto y se detiene antes de montar el viewmodel.
	var measured_length := _model_length(root)
	if measured_length <= 0.0:
		push_error("GLB de Glock roto: no contiene geometria medible")
		return false
	if absf(measured_length - ASSET_LENGTH_M) > 0.003:
		push_error("GLB de Glock fuera de contrato: largo %.1f mm, esperado %.1f mm" % [measured_length * 1000.0, ASSET_LENGTH_M * 1000.0])
		return false
	model_scale = 1.0
	scale = Vector3.ONE
	## El brazo de palanca se mide DESPUES de escalar: `_lever` mide en mundo y
	## TRIGGER_TRAVEL esta en metros. Con escala canonica 1.0 es identidad.
	_trigger_lever = _lever(trigger)
	if _trigger_lever <= 0.0:
		push_error("GLB de Glock roto: Trigger no tiene brazo de palanca medible")
		return false
	# El recorrido visible se ancla al real, no al hueco de la malla.
	_slide_travel = SLIDE_TRAVEL / model_scale
	if not _build_cartridge():
		return false
	_bind_materials(root)

	print("ARMA Glock 19 escala=", snappedf(model_scale, 0.0001),
		" largo_modelo_m=", snappedf(measured_length, 0.001),
		" corredera=", snappedf(SLIDE_TRAVEL * 1000.0, 0.1), "mm",
		" gatillo=", snappedf(TRIGGER_TRAVEL / _trigger_lever * 57.2958, 0.1), "grados",
		" piezas=Frame/Slide/Barrel/Trigger/Magazine + 6 sockets")
	return true


## Cartucho 9x19 en la recamara: laton 19,15 mm + punta cobriza. Nace mirando
## a la boca (eje Y del cilindro sobre la linea boca-origen del cañon) con el
## culote en la cara de culata. Sin slide abierto no se ve; con slide abierto y
## `chamber == 0` tampoco: inspeccionar con recamara vacia muestra vacio.
func _build_cartridge() -> bool:
	assert(barrel != null and muzzle != null)
	cartridge = Node3D.new()
	cartridge.name = "Cartridge"
	barrel.add_child(cartridge)
	# Eje del anima MEDIDO: del origen del canon a su corona (~100 mm en la
	# malla). Si algun GLB futuro lo trae degenerado, se avisa en vez de
	# inventar un eje en el marco equivocado.
	var bore: Vector3 = (muzzle.position - Vector3.ZERO)
	if bore.length() < 0.01:
		push_error("GLB de Glock roto: Muzzle no define un eje de anima medible")
		return false
	bore = bore.normalized()
	var right: Vector3 = bore.cross(Vector3.UP)
	if right.length() < 0.01:
		push_error("GLB de Glock roto: el eje del anima no permite construir el cartucho")
		return false
	right = right.normalized()
	cartridge.basis = Basis(right, bore, right.cross(bore))
	# La recamara se MIDE: el culote va sobre la cara de culata (centroide de
	# los vertices traseros del canon sobre el eje del anima). El origen del
	# nodo Barrel no esta garantizado sobre el anima: plantarlo en cero lo
	# dejaba flotando al lado derecho de la corredera en inspeccion.
	var breech_face = _breech_face(barrel, bore)
	if breech_face == null:
		return false
	cartridge.position = breech_face
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.53, 0.18)
	brass.metallic = 0.9
	brass.roughness = 0.35
	var case_mesh := CylinderMesh.new()
	case_mesh.top_radius = 0.0049
	case_mesh.bottom_radius = 0.0049
	case_mesh.height = 0.01915
	case_mesh.radial_segments = 12
	var case_inst := MeshInstance3D.new()
	case_inst.name = "Case"
	case_inst.mesh = case_mesh
	case_inst.material_override = brass
	case_inst.position = Vector3(0.0, 0.0096, 0.0)
	cartridge.add_child(case_inst)
	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color(0.55, 0.32, 0.18)
	copper.metallic = 0.9
	copper.roughness = 0.4
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0028
	nose_mesh.bottom_radius = 0.0045
	nose_mesh.height = 0.009
	nose_mesh.radial_segments = 12
	var nose_inst := MeshInstance3D.new()
	nose_inst.name = "Bullet"
	nose_inst.mesh = nose_mesh
	nose_inst.material_override = copper
	nose_inst.position = Vector3(0.0, 0.01915 + 0.0045, 0.0)
	cartridge.add_child(nose_inst)
	cartridge.visible = false
	return true


## Cara de culata en espacio del Barrel: vertices a <2 mm de la maxima
## profundidad trasera, recentrados a <10 mm del primer centroide para que un
## resalte (rampa, teton) no tire el eje fuera del anima.
func _breech_face(part: Node3D, bore: Vector3) -> Variant:
	var back := -bore
	var verts: Array[Vector3] = []
	var stack: Array = [part]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			# A espacio del Barrel por cadena de padres (vale anidado y sin
			# globales asentados).
			var xform := Transform3D.IDENTITY
			if mi != part:
				xform = mi.transform
				var par := mi.get_parent()
				while par != null and par != part:
					if par is Node3D:
						xform = (par as Node3D).transform * xform
					par = par.get_parent()
			for s in range(mi.mesh.get_surface_count()):
				for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					verts.append(xform * v)
		for c in n.get_children():
			if c != cartridge:
				stack.append(c)
	if verts.is_empty():
		push_error("GLB de Glock roto: Barrel no tiene vertices para medir la recamara")
		return null
	var deepest := -1e9
	for v in verts:
		deepest = maxf(deepest, v.dot(back))
	var center := Vector3.ZERO
	var count := 0
	for v in verts:
		if deepest - v.dot(back) < 0.002:
			center += v
			count += 1
	if count == 0:
		push_error("GLB de Glock roto: no se pudo medir la cara de culata")
		return null
	center /= float(count)
	var refined := Vector3.ZERO
	var n2 := 0
	for v in verts:
		if deepest - v.dot(back) < 0.002 and v.distance_to(center) < 0.010:
			refined += v
			n2 += 1
	if n2 > 0:
		center = refined / float(n2)
	return center + bore * 0.001


## El cartucho se ve solo con puerto abierto y recamara cargada. Lo decide
## Glock.gd cada frame junto a la corredera.
func set_chamber_visible(v: bool) -> void:
	assert(cartridge != null, "Glock requiere cartucho construido")
	cartridge.visible = v


## Pivote del cabeceo en unidades del WeaponSocket: el Grip MEDIDO en el GLB.
## El nodo es obligatorio; no hay pivote calibrado de reserva.
func grip_pivot() -> Vector3:
	assert(grip != null, "Glock requiere Grip para definir el pivote")
	var p_model: Vector3 = global_transform.affine_inverse() * grip.global_position
	return p_model * model_scale


## Engancha los mapas del repo a las mallas del arma. El .glb sale del
## exportador sin texturas, asi que cada malla recibe un unico
## StandardMaterial3D con los cuatro canales. Se hace una vez por superficie y
## se comparte el material: el arma entera es UNA pieza para el renderer.
func _bind_materials(root: Node) -> void:
	var albedo: Texture2D = load(MAP_BASE_COLOR)
	var orm: Texture2D = load(MAP_SLIDE)
	var emissive: Texture2D = load(MAP_EMISSIVE)
	var normal: Texture2D = load(MAP_NORMAL)
	if albedo == null or orm == null or normal == null:
		push_error("Faltan los mapas obligatorios de la Glock en assets/models")
		return
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/glock_pbr.gdshader")
	mat.resource_name = "Glock_PBR"
	mat.set_shader_parameter("albedo_tex", albedo)
	mat.set_shader_parameter("orm_tex", orm)
	mat.set_shader_parameter("normal_tex", normal)
	mat.set_shader_parameter("emission_tex", emissive)
	mat.set_shader_parameter("normal_strength", 1.0)
	mat.set_shader_parameter("emission_energy", 0.35)
	var stack: Array = [root]
	var bound := 0
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is MeshInstance3D:
			(node as MeshInstance3D).material_override = mat
			bound += 1
		for c in node.get_children():
			stack.append(c)
	print("ARMA texturas externas enganchadas en %d mallas (glb sin texturas)" % bound)


func _find_child(root: Node, node_name: String) -> Node3D:
	if root.name == node_name and root is Node3D:
		return root as Node3D
	for c in root.get_children():
		var r := _find_child(c, node_name)
		if r != null:
			return r
	return null


func _model_length(root: Node) -> float:
	var box := _mesh_aabb(root)
	return maxf(box.size.x, maxf(box.size.y, box.size.z))


## Caja de todas las mallas del arma, medida en el espacio del ARMA.
##
## Ojo: la AABB de cada malla hay que llevarla con su transform de MUNDO, no con
## el local. Las piezas que traen su propio origen (Trigger, Barrel) tienen
## transform local, y con el local la caja mide de mas y el arma se escala de
## menos.
func _mesh_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var inverse := (root as Node3D).global_transform.affine_inverse()
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local_box: AABB = (inverse * (n as Node3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
			box = local_box if first else box.merge(local_box)
			first = false
		for c in n.get_children():
			stack.append(c)
	return box


## Corredera: 0 = cerrada, 1 = atras del todo. UNICA autoridad: Glock.gd.
## El sentido lo da MUZZLE_AXIS: la corredera retrocede al reves de la boca.
func set_slide(t: float) -> void:
	assert(slide != null, "Glock requiere Slide")
	var amount := clampf(t, 0.0, 1.0)
	slide.position = _slide_rest - muzzle_axis * (_slide_travel * amount)
	## Cañon Glock: retrocede JUNTO a la corredera ~4 mm, luego se detiene y cae.
	## Muzzle cuelga de Barrel, asi que el fogonazo no viaja con la corredera.
	var slide_m := SLIDE_TRAVEL * amount
	var joint_m := minf(slide_m, BARREL_LOCK_TRAVEL)
	barrel.position = _barrel_rest - muzzle_axis * (joint_m / model_scale)
	var unlock := clampf((slide_m - BARREL_LOCK_TRAVEL) / (SLIDE_TRAVEL - BARREL_LOCK_TRAVEL), 0.0, 1.0)
	barrel.transform.basis = Basis(Quaternion(SIDE_AXIS, -BARREL_DROP * unlock)) * _barrel_rest_basis


## Brazo de palanca del gatillo EN METROS DE MUNDO: distancia PERPENDICULAR al
## eje del pasador (plano YZ), del vertice mas lejano al eje. Perpendicular y no
## 3D: un origen desplazado en X (herencia del asset vieja) inflaba el radio y
## dejaba el recorrido un 22% corto. Se mide en mundo porque TRIGGER_TRAVEL esta
## en metros.
func _lever(part: Node3D) -> float:
	var radius := 0.0
	var pivot: Vector3 = part.global_transform.origin
	var stack: Array = [part]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh_instance: MeshInstance3D = n as MeshInstance3D
			var mesh: Mesh = mesh_instance.mesh
			for s in range(mesh.get_surface_count()):
				var vertices: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v: Vector3 in vertices:
					var rel: Vector3 = (mesh_instance.global_transform * v) - pivot
					var perp := Vector2(rel.y, rel.z).length()
					radius = maxf(radius, perp)
		for c in n.get_children():
			stack.append(c)
	return radius


## Gatillo: 0 = suelto, 1 = a fondo. UNICA autoridad: Glock.gd.
## Gira sobre el pasador, que es el ORIGEN de la pieza: por eso el giro se
## aplica sobre la base del padre y no sobre la de la pieza.
## El GLB canónico siempre trae Trigger; si falta, `build()` detiene el arma.
func set_trigger(t: float) -> void:
	assert(trigger != null, "Glock requiere Trigger")
	var angle := -(TRIGGER_TRAVEL / _trigger_lever) * clampf(t, 0.0, 1.0)
	trigger.transform.basis = Basis(Quaternion(SIDE_AXIS, angle)) * _trigger_rest_basis


## Cargador: distancia desde el brocal, EN METROS (0 = asentado, positivo =
## fuera del arma, cayendo). UNICA autoridad: Glock.gd, que le pasa la
## coreografia de la recarga. Aqui solo se convierte a unidades del modelo: el
## cargador entra y sale por MAGAZINE_OUT_AXIS, que es el del modelo.
func set_magazine_offset(offset_m: float) -> void:
	assert(magazine != null, "Glock requiere Magazine")
	magazine.position = magazine_rest + MAGAZINE_OUT_AXIS * (offset_m / model_scale)


## Tumba del cargador (radianes sobre el eje lateral del arma): el vacio cae
## girando, el lleno entra inclinado y se endereza. UNICA autoridad: Glock.gd.
func set_magazine_tumble(angle: float) -> void:
	assert(magazine != null, "Glock requiere Magazine")
	magazine.transform.basis = Basis(Quaternion(SIDE_AXIS, angle)) * _magazine_rest_basis


## Cargador: dentro del arma o fuera. UNICA autoridad: Glock.gd.
func set_magazine_attached(attached: bool) -> void:
	assert(magazine != null, "Glock requiere Magazine")
	magazine.visible = attached


## Eje por el que el cargador sale del arma, en espacio del arma. CALIBRADO
## sobre la malla: el cargador cuelga por debajo del armazon y su padre no
## aporta rotacion (verificado con tools/check_weapon.gd).
func magazine_out_axis() -> Vector3:
	return (global_transform.basis * MAGAZINE_OUT_AXIS).normalized()
