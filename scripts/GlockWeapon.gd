class_name GlockWeapon
extends Node3D

## EL ARMA: la Glock 19 en piezas rigidas, sin esqueleto y sin tabla.
##
## El .glb del arma (lo prepara tools/build_g19_parts.py) trae las piezas como
## nodos, cada una con su PROPIO origen:
##
##   Frame      armazon. Es el origen del arma y no lo mueve nadie.
##   Slide      corredera            <- set_slide(0..1)       (Glock.gd)
##   Magazine   cargador             <- set_magazine_offset   (Glock.gd)
##   Trigger    gatillo              <- set_trigger(0..1)     (Glock.gd)
##   Barrel     cañon                <- cae con la corredera (set_slide)
##   Muzzle / EjectionPort / SightRear / SightFront
##              puntos medidos sobre la malla, colgados de la corredera.
##
## El asset es la "G19 Pistol, Game Ready" de Rotuma (CC-BY 4.0). Ese archivo
## trae la pistola DOS veces dentro de una sola malla: armada y despiezada, mas
## un cargador de repuesto y tres piezas flotantes del expositor. El script
## tools/build_g19_parts.py se queda con la copia armada, la reparte por islas,
## recorta el gatillo del armazon y reasienta los origenes. Siguen siendo
## opcionales: si faltan, el arma funciona igual y `build()` lo dice por consola.
##
## AQUI NO HAY GAMEPLAY: la autoridad de cada pieza es `Glock.gd`, y este archivo
## solo la representa. Los unicos numeros que viven aqui son los del arma fisica.
##
##   "la corredera no llega" -> SLIDE_TRAVEL
##   "el arma esta mal encuadrada" -> GlockViewmodel.GRIP_POS / GRIP_ROT

const MODEL := "res://assets/models/g19_pistol.glb"
## Largo real de la pistola, extremo a extremo. De aqui sale la escala del
## modelo: no hay que calibrarla a mano. El asset de Rotuma ya viene a esa
## medida (174 mm de largo y 127 mm de alto medidos en su malla); si algun dia
## se cambia, la escala lo corrige.
const REAL_LENGTH := 0.174
## Recorrido real de la corredera. Es la unica autoridad del recorrido: la
## mecanica de Glock.gd y el dibujo la leen de aqui.
const SLIDE_TRAVEL := 0.039
## Cartuchos que entran en el cargador. El 9x19 de la Glock 19 son 17.
const MAG_CAPACITY := 17
## Hacia donde mira la boca de la malla, en el espacio del arma. En este asset
## el morro esta a +Z (lo confirman la boca, la mira delantera y el corredor del
## cañon, que son los tres hacia +Z). La corredera retrocede al reves de la boca:
## con el signo cambiado recorria 39 mm HACIA ADELANTE y el arma se veia abierta.
## Lo vigila `tools/check_weapon.gd`.
const MUZZLE_AXIS := Vector3(0.0, 0.0, 1.0)
## Recorrido real del cargador fuera del brocal, de asentado a libre.
const MAG_TRAVEL := 0.07
## Eje de salida del cargador en espacio del arma (abajo del armazon).
const MAGAZINE_OUT_AXIS := Vector3(0.0, -1.0, 0.0)
## Recorrido real del gatillo, medido en la punta del diente. Son los ~5 mm que
## anda el disparador de una Glock de suelto a fondo.
const TRIGGER_TRAVEL := 0.005
## Cuanto baja el cañon cuando la corredera esta atras del todo. El bloqueo lo
## suelta el armazon y la recamara cae; son ~1,5 grados sobre la cara de culata.
const BARREL_DROP := 0.026
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

var _slide_rest := Vector3.ZERO
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
	if frame == null or slide == null or magazine == null:
		push_warning("El arma no trae Frame/Slide/Magazine")
		return

	_slide_rest = slide.position
	magazine_rest = magazine.position
	_magazine_rest_basis = magazine.transform.basis
	if trigger != null:
		_trigger_rest_basis = trigger.transform.basis
	if barrel != null:
		_barrel_rest_basis = barrel.transform.basis

	# La escala sale de medir el largo de la malla contra el largo REAL del arma.
	var measured_length := _model_length(root)
	model_scale = REAL_LENGTH / maxf(measured_length, 0.0001)
	scale = Vector3(model_scale, model_scale, model_scale)
	## El brazo de palanca se mide DESPUES de escalar: `_lever` mide en mundo y
	## TRIGGER_TRAVEL esta en metros, asi que los dos tienen que hablar de lo
	## mismo. Medido antes de escalar salia 8 veces largo y el gatillo andaba
	## 0,6 mm en vez de 5.
	if trigger != null:
		_trigger_lever = maxf(_lever(trigger), 0.001)
	# El recorrido visible se ancla al real, no al hueco de la malla.
	_slide_travel = SLIDE_TRAVEL / model_scale

	var missing: Array = []
	for pair in [["Trigger", trigger], ["Barrel", barrel], ["Muzzle", muzzle], ["EjectionPort", ejection_port]]:
		if pair[1] == null:
			missing.append(pair[0])
	print("ARMA Glock 19 escala=", snappedf(model_scale, 0.0001),
		" largo_modelo_m=", snappedf(measured_length, 0.001),
		" corredera=", snappedf(SLIDE_TRAVEL * 1000.0, 0.1), "mm",
		" gatillo=", snappedf(TRIGGER_TRAVEL / _trigger_lever * 57.2958, 0.1), "grados",
		" sin_pieza=", missing if not missing.is_empty() else "nada")


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
	## El cañon no viaja con la corredera: cae. Con la corredera atras del todo
	## la recamara asoma por el puerto de eyeccion y el arma queda "abierta".
	if barrel != null:
		barrel.transform.basis = Basis(Quaternion(SIDE_AXIS, -BARREL_DROP * amount)) * _barrel_rest_basis


## Brazo de palanca del gatillo EN METROS DE MUNDO: el pasador es el origen de
## la pieza, asi que la distancia al vertice mas lejano es la que convierte
## "5 mm de recorrido" en radianes. Se mide en mundo (no en unidades del
## modelo) porque TRIGGER_TRAVEL esta en metros: mezclar las dos escalas dejaba
## el gatillo girando 0,6 grados en vez de 4,5.
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
					radius = maxf(radius, (mesh_instance.global_transform * v).distance_to(pivot))
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
