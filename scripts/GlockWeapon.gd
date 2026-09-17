class_name GlockWeapon
extends Node3D

## EL ARMA: piezas rigidas, sin esqueleto.
##
## Este nodo es el DUEÑO del arma visible. Su contenido es
## `assets/models/glock_urpo.glb`: la pistola de Urpo (CC-BY 4.0) con una pieza
## por nodo, cada una con su propio origen (ver tools/make_weapon_parts.py).
##
## AUTORIDAD (una sola por pieza):
##   Frame ....... nadie. Es el origen del arma.
##   Slide ....... `set_slide(0..1)`  -> lo llama Glock.gd
##   Trigger ..... `set_trigger(0..1)` -> lo define el arma; el modelo de Urpo no
##                 trae el gatillo suelto, asi que hoy no se mueve. Un arma que
##                 si lo traiga (Desert Eagle) lo mueve con la misma llamada.
##   Magazine .... `set_magazine_attached(bool)` -> lo llama Glock.gd
##   Muzzle / EjectionPort / SightRear / SightFront -> puntos medidos sobre la
##                 malla de la corredera; viajan con ella.
##
## Cambiar el arma = cambiar este archivo y el .glb. Añadirle realismo = editar
## la malla de UNA pieza. Nada de huesos.

const RUTA := "res://assets/models/glock_urpo.glb"
# Largo real de una Glock 19 (m). El GLB viene en unidades del autor (1.479 de
# largo), asi que la escala sale de medir la malla, no de un numero a ojo.
const LARGO_REAL := 0.187

var frame: Node3D
var slide: Node3D
var magazine: Node3D
var muzzle: Node3D
var ejection_port: Node3D
var sight_rear: Node3D
var sight_front: Node3D

## Recorrido real de la corredera de una G19 (m). Manda sobre la medida de la
## malla: la corredera de una Glock recorre 39 mm, no el hueco entero del arma.
const CORREDERA_REAL := 0.039

var _slide_rest := Vector3.ZERO
## Sitio exacto del cargador dentro del arma. Lo usa el viewmodel para
## devolverlo al brocal cuando la mano lo suelta.
var magazine_rest := Vector3.ZERO
## Recorrido de la corredera en unidades del modelo (metros reales / escala).
var _slide_travel := 0.0
var escala := 1.0


func build() -> void:
	var packed := load(RUTA) as PackedScene
	if packed == null:
		push_warning("No se pudo cargar el arma: " + RUTA)
		return
	var raiz := packed.instantiate()
	add_child(raiz)

	frame = _buscar(raiz, "Frame")
	slide = _buscar(raiz, "Slide")
	magazine = _buscar(raiz, "Magazine")
	muzzle = _buscar(raiz, "Muzzle")
	ejection_port = _buscar(raiz, "EjectionPort")
	sight_rear = _buscar(raiz, "SightRear")
	sight_front = _buscar(raiz, "SightFront")
	if frame == null or slide == null or magazine == null:
		push_warning("El arma no trae Frame/Slide/Magazine")
		return

	_slide_rest = slide.position
	magazine_rest = magazine.position
	# La escala sale del largo REAL medido sobre la malla: si el autor entrega
	# el modelo en otra unidad, esto lo corrige solo.
	var largo := _largo(raiz)
	escala = LARGO_REAL / maxf(largo, 0.0001)
	scale = Vector3(escala, escala, escala)
	# El recorrido visible se ancla al real de la G19, no al hueco de la malla.
	_slide_travel = CORREDERA_REAL / escala
	print("ARMA ok escala=", snappedf(escala, 0.0001), " largo_modelo=", snappedf(largo, 3),
		" corredera=", CORREDERA_REAL * 1000.0, " mm")


## Busca un nodo por nombre en todo el arbol importado.
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
	return caja.size.z if caja.size.z > 0.0 else 1.0


func _caja_malla(raiz: Node) -> AABB:
	var caja := AABB()
	var primero := true
	var pila: Array = [raiz]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local: AABB = (n as MeshInstance3D).mesh.get_aabb()
			var mundo: AABB = (n as Node3D).transform * local
			caja = mundo if primero else caja.merge(mundo)
			primero = false
		for c in n.get_children():
			pila.append(c)
	return caja


## Corredera: 0 = cerrada, 1 = atras del todo. UNICA autoridad: Glock.gd.
func set_slide(t: float) -> void:
	if slide == null:
		return
	slide.position = _slide_rest + Vector3(0.0, 0.0, _slide_travel * clampf(t, 0.0, 1.0))


## Gatillo: 0 = suelto, 1 = a fondo. UNICA autoridad: Glock.gd.
func set_trigger(t: float) -> void:
	# El modelo actual no trae el gatillo como pieza suelta: no hay nada que
	# mover. Se deja el punto de entrada para que un arma que si lo traiga
	# (p. ej. la Desert Eagle, con Trigger_low propio) no cambie la arquitectura.
	pass


## Cargador: dentro del arma o fuera. UNICA autoridad: Glock.gd.
func set_magazine_attached(attached: bool) -> void:
	if magazine != null:
		magazine.visible = attached


func magazine_position() -> Vector3:
	return magazine.global_position if magazine != null else global_position
