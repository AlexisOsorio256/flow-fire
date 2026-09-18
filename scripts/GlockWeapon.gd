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
##              cargador). Sin heuristicas AABB en runtime.
##
## Muzzle cuelga de Barrel en el GLB: el fogonazo no viaja con la corredera.
## El reparent en build queda como red por si un GLB futuro lo trae mal.
##
## AQUI NO HAY GAMEPLAY: la autoridad de cada pieza es `Glock.gd`, y este archivo
## solo la representa. Los unicos numeros que viven aqui son los del arma fisica.
##
##   "la corredera no llega" -> SLIDE_TRAVEL
##   "el arma esta mal encuadrada" -> GlockViewmodel.GRIP_POS / GRIP_ROT

const MODEL := "res://assets/models/g19_pistol.glb"
## Largo de la MALLA actual, extremo a extremo (174 mm medidos). No es la ficha:
## la Gen5 real mide 185 mm. El GLB canonico llega ya en metros; Godot solo
## VALIDA, no corrige en silencio (avisa si la escala se desvia >3%).
const REAL_LENGTH := 0.174
const REFERENCE_LENGTH := 0.185
const REFERENCE_NAME := "Glock 19 Gen5 stock"
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


func build() -> void:
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_warning("No se pudo cargar el arma: " + MODEL)
		return
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
	if frame == null or slide == null or magazine == null:
		push_warning("El arma no trae Frame/Slide/Magazine")
		return

	_slide_rest = slide.position
	if barrel != null:
		_barrel_rest = barrel.position
	magazine_rest = magazine.position
	_magazine_rest_basis = magazine.transform.basis
	if trigger != null:
		_trigger_rest_basis = trigger.transform.basis
	if barrel != null:
		_barrel_rest_basis = barrel.transform.basis

	# El GLB canonico llega en metros: se VALIDA. Dentro del 3% la escala es 1.0
	# exacta (cero correccion silenciosa); fuera, se corrige y se avisa alto.
	var measured_length := _model_length(root)
	var raw_scale := REAL_LENGTH / maxf(measured_length, 0.0001)
	if absf(raw_scale - 1.0) > 0.03:
		push_warning("GLB no canonico: escala %.4f (malla %.1f mm)" % [raw_scale, measured_length * 1000.0])
		model_scale = raw_scale
	else:
		model_scale = 1.0
	scale = Vector3(model_scale, model_scale, model_scale)
	## El brazo de palanca se mide DESPUES de escalar: `_lever` mide en mundo y
	## TRIGGER_TRAVEL esta en metros. Con escala canonica 1.0 es identidad.
	if trigger != null:
		_trigger_lever = maxf(_lever(trigger), 0.001)
	# El recorrido visible se ancla al real, no al hueco de la malla.
	_slide_travel = SLIDE_TRAVEL / model_scale
	if barrel != null and muzzle != null and muzzle.get_parent() != barrel:
		var g := muzzle.global_transform
		barrel.add_child(muzzle)
		muzzle.global_transform = g
	_build_cartridge()

	var missing: Array = []
	for pair in [["Trigger", trigger], ["Barrel", barrel], ["Muzzle", muzzle], ["EjectionPort", ejection_port], ["Grip", grip], ["Magwell", magwell]]:
		if pair[1] == null:
			missing.append(pair[0])
	print("ARMA Glock 19 escala=", snappedf(model_scale, 0.0001),
		" largo_modelo_m=", snappedf(measured_length, 0.001),
		" corredera=", snappedf(SLIDE_TRAVEL * 1000.0, 0.1), "mm",
		" gatillo=", snappedf(TRIGGER_TRAVEL / _trigger_lever * 57.2958, 0.1), "grados",
		" sin_pieza=", missing if not missing.is_empty() else "nada")


## Cartucho 9x19 en la recamara: laton 19,15 mm + punta cobriza. Nace mirando
## a la boca (eje Y del cilindro sobre la linea boca-origen del cañon) con el
## culote en la cara de culata. Sin slide abierto no se ve; con slide abierto y
## `chamber == 0` tampoco: inspeccionar con recamara vacia muestra vacio.
func _build_cartridge() -> void:
	if barrel == null or muzzle == null:
		return
	cartridge = Node3D.new()
	cartridge.name = "Cartridge"
	barrel.add_child(cartridge)
	var bore: Vector3 = (muzzle.position - Vector3.ZERO)
	if bore.length() < 0.01:
		bore = -muzzle_axis
	bore = bore.normalized()
	var right: Vector3 = bore.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	cartridge.basis = Basis(right, bore, right.cross(bore))
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


## El cartucho se ve solo con puerto abierto y recamara cargada. Lo decide
## Glock.gd cada frame junto a la corredera.
func set_chamber_visible(v: bool) -> void:
	if cartridge != null:
		cartridge.visible = v


## Pivote del cabeceo en unidades del WeaponSocket: el Grip MEDIDO en el GLB.
## Sin el nodo, aproximacion calibrada (pendiente de nada: el GLB lo trae).
func grip_pivot() -> Vector3:
	if grip != null:
		var p_model: Vector3 = global_transform.affine_inverse() * grip.global_position
		return p_model * model_scale
	return Vector3(0.0, -0.055, 0.025)


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
	if slide == null:
		return
	var amount := clampf(t, 0.0, 1.0)
	slide.position = _slide_rest - muzzle_axis * (_slide_travel * amount)
	## Cañon Glock: retrocede JUNTO a la corredera ~4 mm, luego se detiene y cae.
	## Muzzle cuelga de Barrel, asi que el fogonazo no viaja con la corredera.
	if barrel != null:
		var slide_m := SLIDE_TRAVEL * amount
		var joint_m := minf(slide_m, BARREL_LOCK_TRAVEL)
		barrel.position = _barrel_rest - muzzle_axis * (joint_m / maxf(model_scale, 0.0001))
		var unlock := clampf((slide_m - BARREL_LOCK_TRAVEL) / maxf(SLIDE_TRAVEL - BARREL_LOCK_TRAVEL, 0.0001), 0.0, 1.0)
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
## Si el modelo no trae el gatillo como pieza suelta no hay nada que mover, y el
## arma sigue funcionando igual.
func set_trigger(t: float) -> void:
	if trigger == null:
		return
	var angle := -(TRIGGER_TRAVEL / _trigger_lever) * clampf(t, 0.0, 1.0)
	trigger.transform.basis = Basis(Quaternion(SIDE_AXIS, angle)) * _trigger_rest_basis


## Cargador: distancia desde el brocal, EN METROS (0 = asentado, positivo =
## fuera del arma, cayendo). UNICA autoridad: Glock.gd, que le pasa la
## coreografia de la recarga. Aqui solo se convierte a unidades del modelo: el
## cargador entra y sale por MAGAZINE_OUT_AXIS, que es el del modelo.
func set_magazine_offset(offset_m: float) -> void:
	if magazine == null:
		return
	magazine.position = magazine_rest + MAGAZINE_OUT_AXIS * (offset_m / maxf(model_scale, 0.0001))


## Tumba del cargador (radianes sobre el eje lateral del arma): el vacio cae
## girando, el lleno entra inclinado y se endereza. UNICA autoridad: Glock.gd.
func set_magazine_tumble(angle: float) -> void:
	if magazine == null:
		return
	magazine.transform.basis = Basis(Quaternion(SIDE_AXIS, angle)) * _magazine_rest_basis


## Cargador: dentro del arma o fuera. UNICA autoridad: Glock.gd.
func set_magazine_attached(attached: bool) -> void:
	if magazine != null:
		magazine.visible = attached


## Eje por el que el cargador sale del arma, en espacio del arma. CALIBRADO
## sobre la malla: el cargador cuelga por debajo del armazon y su padre no
## aporta rotacion (verificado con tools/check_weapon.gd).
func magazine_out_axis() -> Vector3:
	return (global_transform.basis * MAGAZINE_OUT_AXIS).normalized()
