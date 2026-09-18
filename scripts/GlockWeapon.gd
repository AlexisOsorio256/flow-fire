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
##   "la corredera no llega" -> CORREDERA
##   "el arma esta mal encuadrada" -> GlockViewmodel.GRIP_POS / GRIP_ROT

const MALLA := "res://assets/models/g19_pistol.glb"
## Largo real de la pistola, extremo a extremo. De aqui sale la escala del
## modelo: no hay que calibrarla a mano. 174 mm es la Glock 19 de verdad, y el
## asset ya viene a esa medida; si algun dia se cambia, la escala lo corrige.
const LARGO := 0.174
## Recorrido real de la corredera. Es la unica autoridad del recorrido: la
## mecanica de Glock.gd y el dibujo la leen de aqui.
const CORREDERA := 0.039
## Cartuchos que entran en el cargador. El 9x19 de la Glock 19 son 17.
const CARGADOR := 17
## La boca del arma en la malla. La corredera retrocede al reves.
const ADELANTE := Vector3(0.0, 0.0, -1.0)
## Recorrido real del cargador fuera del brocal, de asentado a libre.
const MAG_FUERA := 0.07
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

var corredera := CORREDERA
var capacidad := CARGADOR
var adelante := ADELANTE
var escala := 1.0

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
## Recorrido del cargador en unidades del modelo (metros reales / escala).
var _mag_travel := 0.0
## Sitio exacto del cargador dentro del arma. Lo usa el viewmodel para
## devolverlo al brocal cuando la mano lo suelta.
var magazine_rest := Vector3.ZERO


func build() -> void:
	var packed := load(MALLA) as PackedScene
	if packed == null:
		push_warning("No se pudo cargar el arma: " + MALLA)
		return
	var raiz := packed.instantiate()
	add_child(raiz)

	frame = _buscar(raiz, "Frame")
	slide = _buscar(raiz, "Slide")
	magazine = _buscar(raiz, "Magazine")
	trigger = _buscar(raiz, "Trigger")
	barrel = _buscar(raiz, "Barrel")
	muzzle = _buscar(raiz, "Muzzle")
	ejection_port = _buscar(raiz, "EjectionPort")
	sight_rear = _buscar(raiz, "SightRear")
	sight_front = _buscar(raiz, "SightFront")
	if frame == null or slide == null or magazine == null:
		push_warning("El arma no trae Frame/Slide/Magazine")
		return

	_slide_rest = slide.position
	magazine_rest = magazine.position
	if trigger != null:
		_trigger_rest_basis = trigger.transform.basis
	if barrel != null:
		_barrel_rest_basis = barrel.transform.basis

	# La escala sale de medir el largo de la malla contra el largo REAL del arma.
	var largo_medido := _largo(raiz)
	escala = LARGO / maxf(largo_medido, 0.0001)
	scale = Vector3(escala, escala, escala)
	## El brazo de palanca se mide DESPUES de escalar: `_lever` mide en mundo y
	## TRIGGER_TRAVEL esta en metros, asi que los dos tienen que hablar de lo
	## mismo. Medido antes de escalar salia 8 veces largo y el gatillo andaba
	## 0,6 mm en vez de 5.
	if trigger != null:
		_trigger_lever = maxf(_lever(trigger), 0.001)
	# El recorrido visible se ancla al real, no al hueco de la malla.
	_slide_travel = CORREDERA / escala
	_mag_travel = MAG_FUERA / escala

	var faltan: Array = []
	for par in [["Trigger", trigger], ["Barrel", barrel], ["Muzzle", muzzle], ["EjectionPort", ejection_port]]:
		if par[1] == null:
			faltan.append(par[0])
	print("ARMA Glock 19 escala=", snappedf(escala, 0.0001),
		" largo_modelo_m=", snappedf(largo_medido, 0.001),
		" corredera=", snappedf(CORREDERA * 1000.0, 0.1), "mm",
		" gatillo=", snappedf(TRIGGER_TRAVEL / _trigger_lever * 57.2958, 0.1), "grados",
		" sin_pieza=", faltan if not faltan.is_empty() else "nada")


func _buscar(raiz: Node, nombre: String) -> Node3D:
	if raiz.name == nombre and raiz is Node3D:
		return raiz as Node3D
	for c in raiz.get_children():
		var r := _buscar(c, nombre)
		if r != null:
			return r
	return null


func _largo(raiz: Node) -> float:
	var caja := _caja_malla(raiz)
	return maxf(caja.size.x, maxf(caja.size.y, caja.size.z))


## Caja de todas las mallas del arma, medida en el espacio del ARMA.
##
## Ojo: la AABB de cada malla hay que llevarla con su transform de MUNDO, no con
## el local. Las piezas que traen su propio origen (Trigger, Barrel) tienen
## transform local, y con el local la caja salia un 5% mas larga y el arma se
## escalaba de menos (176,9 mm en vez de 187).
func _caja_malla(raiz: Node) -> AABB:
	var caja := AABB()
	var primero := true
	var inversa := (raiz as Node3D).global_transform.affine_inverse()
	var pila: Array = [raiz]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local: AABB = (inversa * (n as Node3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
			caja = local if primero else caja.merge(local)
			primero = false
		for c in n.get_children():
			pila.append(c)
	return caja


## Corredera: 0 = cerrada, 1 = atras del todo. UNICA autoridad: Glock.gd.
## El sentido lo da `adelante`: la corredera retrocede al reves de la boca.
func set_slide(t: float) -> void:
	if slide == null:
		return
	var avance := clampf(t, 0.0, 1.0)
	slide.position = _slide_rest - adelante * (_slide_travel * avance)
	## El cañon no viaja con la corredera: cae. Con la corredera atras del todo
	## la recamara asoma por el puerto de eyeccion y el arma queda "abierta".
	if barrel != null:
		barrel.transform.basis = Basis(Quaternion(SIDE_AXIS, -BARREL_DROP * avance)) * _barrel_rest_basis


## Brazo de palanca del gatillo EN METROS DE MUNDO: el pasador es el origen de
## la pieza, asi que la distancia al vertice mas lejano es la que convierte
## "5 mm de recorrido" en radianes. Se mide en mundo (no en unidades del
## modelo) porque TRIGGER_TRAVEL esta en metros: mezclar las dos escalas dejaba
## el gatillo girando 0,6 grados en vez de 4,5.
func _lever(pieza: Node3D) -> float:
	var radio := 0.0
	var origen: Vector3 = pieza.global_transform.origin
	var pila: Array = [pieza]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var malla: MeshInstance3D = n as MeshInstance3D
			var mesh: Mesh = malla.mesh
			for s in range(mesh.get_surface_count()):
				var vertices: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v: Vector3 in vertices:
					radio = maxf(radio, (malla.global_transform * v).distance_to(origen))
		for c in n.get_children():
			pila.append(c)
	return radio


## Gatillo: 0 = suelto, 1 = a fondo. UNICA autoridad: Glock.gd.
## Gira sobre el pasador, que es el ORIGEN de la pieza: por eso el giro se
## aplica sobre la base del padre y no sobre la de la pieza.
## Si el modelo no trae el gatillo como pieza suelta no hay nada que mover, y el
## arma sigue funcionando igual.
func set_trigger(t: float) -> void:
	if trigger == null:
		return
	var angulo := -(TRIGGER_TRAVEL / _trigger_lever) * clampf(t, 0.0, 1.0)
	trigger.transform.basis = Basis(Quaternion(SIDE_AXIS, angulo)) * _trigger_rest_basis


## Cargador: 0 = asentado en el brocal, 1 = fuera del todo. UNICA autoridad:
## Glock.gd, que le pasa su avance en la recarga. El eje de salida es el del
## propio modelo (el cargador cuelga por debajo del arma) y el recorrido es el
## real: MAG_FUERA.
func set_magazine_offset(t: float) -> void:
	if magazine == null:
		return
	magazine.position = magazine_rest + MAGAZINE_OUT_AXIS * (_mag_travel * clampf(t, 0.0, 1.0))


## Cargador: dentro del arma o fuera. UNICA autoridad: Glock.gd.
func set_magazine_attached(attached: bool) -> void:
	if magazine != null:
		magazine.visible = attached


## Eje por el que el cargador sale del arma, en espacio del arma. CALIBRADO
## sobre la malla: el cargador cuelga por debajo del armazon y su padre no
## aporta rotacion (verificado con tools/check_weapon.gd).
func magazine_out_axis() -> Vector3:
	return (global_transform.basis * MAGAZINE_OUT_AXIS).normalized()
