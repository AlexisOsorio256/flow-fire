class_name GlockWeapon
extends Node3D

## EL ARMA: piezas rigidas, sin esqueleto.
##
## Cada arma es una entrada de la tabla ARMAS de abajo. NO hay codigo por arma:
## cambiar de modelo o anadir otro es anadir una entrada y su .glb, nada mas.
##
## Un .glb de arma (lo prepara tools/make_weapon_parts.py) trae las piezas como
## nodos, cada una con su PROPIO origen:
##
##   Frame      armazon. Es el origen del arma y no lo mueve nadie.
##   Slide      corredera            <- set_slide(0..1)       (Glock.gd)
##   Trigger    gatillo              <- set_trigger(0..1)     (Glock.gd)
##   Magazine   cargador             <- set_magazine_attached (Glock.gd)
##   Barrel     cañon. Opcional: se queda quieto con el armazon.
##   Muzzle / EjectionPort / SightRear / SightFront
##              puntos medidos sobre la malla, colgados de la corredera.
##
## DONDE SE PIDE CADA COSA
##
##   "el recoil se ve falso"     -> scripts/GlockRecoil.gd (3 constantes juntas)
##   "el arma esta mal encuadrada" -> GlockViewmodel.ARMA_EMPUNADURA (1 linea)
##   "la corredera no llega"     -> `corredera` en la tabla de abajo
##   "quiero otra pistola"       -> `arma` en GlockViewmodel + entrada aqui + .glb
##
## La autoridad de cada pieza es siempre Glock.gd: aqui solo se representa.

## Tabla de armas. `largo` y `corredera` van en METROS reales: la escala sale de
## dividir por el largo medido de la propia malla, asi que un modelo nuevo entra
## sin calibrar nada a mano.
const ARMAS := {
	"glock": {
		"ruta": "res://assets/models/glock_urpo.glb",
		"nombre": "Glock 19",
		"largo": 0.187,
		"corredera": 0.039,
		"adelante": Vector3(0.0, 0.0, -1.0),
		"cargador": 17,
	},
	"de": {
		"ruta": "res://assets/models/desert_eagle.glb",
		"nombre": "Desert Eagle",
		"largo": 0.270,
		"corredera": 0.045,
		"adelante": Vector3(0.0, 0.0, 1.0),
		"cargador": 7,
	},
}

var frame: Node3D
var slide: Node3D
var trigger: Node3D
var magazine: Node3D
var barrel: Node3D
var muzzle: Node3D
var ejection_port: Node3D
var sight_rear: Node3D
var sight_front: Node3D

var escala := 1.0
var capacidad := 17
var adelante := Vector3(0.0, 0.0, -1.0)

var _slide_rest := Vector3.ZERO
var _trigger_rest := Vector3.ZERO
## Recorrido de la corredera en unidades del modelo (metros reales / escala).
var _slide_travel := 0.0
## Sitio exacto del cargador dentro del arma. Lo usa el viewmodel para
## devolverlo al brocal cuando la mano lo suelta.
var magazine_rest := Vector3.ZERO
## Punto del arma que la mano agarra, en espacio local del arma. Es el origen
## del Frame: el armazon nace en la union empunadura-corredera (ver
## tools/make_weapon_parts.py). El viewmodel lo usa para ponerla en la mano.
var empunadura := Vector3.ZERO


func build(clave: String) -> void:
	if not ARMAS.has(clave):
		push_warning("Arma desconocida: " + clave)
		return
	var spec: Dictionary = ARMAS[clave]
	capacidad = int(spec["cargador"])
	adelante = spec["adelante"]

	var packed := load(spec["ruta"]) as PackedScene
	if packed == null:
		push_warning("No se pudo cargar el arma: " + str(spec["ruta"]))
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
		push_warning("El arma " + clave + " no trae Frame/Slide/Magazine")
		return

	_slide_rest = slide.position
	magazine_rest = magazine.position
	empunadura = frame.position
	if trigger != null:
		_trigger_rest = trigger.position

	# La escala sale de medir el largo de la malla contra el largo REAL del arma.
	var largo_medido := _largo(raiz)
	escala = float(spec["largo"]) / maxf(largo_medido, 0.0001)
	scale = Vector3(escala, escala, escala)
	# El recorrido visible se ancla al real, no al hueco de la malla.
	_slide_travel = float(spec["corredera"]) / escala

	var faltan: Array = []
	for par in [["Trigger", trigger], ["Barrel", barrel], ["Muzzle", muzzle], ["EjectionPort", ejection_port]]:
		if par[1] == null:
			faltan.append(par[0])
	print("ARMA ", spec["nombre"], " escala=", snappedf(escala, 0.0001),
		" largo_modelo=", snappedf(largo_medido, 3),
		" corredera=", snappedf(float(spec["corredera"]) * 1000.0, 0.1), "mm",
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


func _caja_malla(raiz: Node) -> AABB:
	var caja := AABB()
	var primero := true
	var pila: Array = [raiz]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mundo: AABB = (n as Node3D).transform * (n as MeshInstance3D).mesh.get_aabb()
			caja = mundo if primero else caja.merge(mundo)
			primero = false
		for c in n.get_children():
			pila.append(c)
	return caja


## Corredera: 0 = cerrada, 1 = atras del todo. UNICA autoridad: Glock.gd.
## El sentido lo da `adelante`: la corredera retrocede al reves de la boca.
func set_slide(t: float) -> void:
	if slide == null:
		return
	slide.position = _slide_rest - adelante * (_slide_travel * clampf(t, 0.0, 1.0))


## Gatillo: 0 = suelto, 1 = a fondo. UNICA autoridad: Glock.gd.
## Si el modelo no trae el gatillo como pieza suelta no hay nada que mover, y el
## arma sigue funcionando igual.
func set_trigger(t: float) -> void:
	if trigger == null:
		return
	trigger.position = _trigger_rest + adelante * (0.005 * clampf(t, 0.0, 1.0))


## Cargador: dentro del arma o fuera. UNICA autoridad: Glock.gd.
func set_magazine_attached(attached: bool) -> void:
	if magazine != null:
		magazine.visible = attached


func magazine_position() -> Vector3:
	return magazine.global_position if magazine != null else global_position
