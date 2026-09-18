extends Node
## INVARIANTES DEL ARMA, sin abrir el editor ni mirar la pantalla.
##
##   godot --headless --path . tools/check_weapon.tscn
##
## Comprueba lo que el ojo no mide: que la pistola este en METROS REALES en el
## mundo (174 mm de largo), que existan las piezas que el juego mueve y que el
## cargador viaje hacia abajo en el espacio del arma. Si algo falla, imprime
## FALLO y sale con codigo 1.

const LARGO_REAL := 0.174
const TOLERANCIA := 0.002
const CORREDERA_REAL := 0.039


func _ready() -> void:
	var vm: Node3D = GlockViewmodel.new()
	add_child(vm)
	vm.mount()
	var arma = vm.get("weapon")
	var fallos := 0

	if arma == null:
		print("FALLO: el arma no monto")
		get_tree().quit(1)
		return

	print("--- ARMA ---")
	print("escala del modelo ", snappedf(arma.escala, 0.0001),
		"  capacidad ", arma.capacidad)

	# El largo se mide DENTRO del arma (unidades del modelo) y se lleva al mundo
	# con la escala que el arma tiene de verdad: asi se caza cualquier escala
	# heredada de un padre (era el bug de los brazos a ARMS_SCALE).
	var escala_mundo: float = arma.global_transform.basis.get_scale().x
	var largo: float = _largo_local(arma) * escala_mundo
	_caja_local(arma, true)
	print("largo en el mundo mm ", snappedf(largo * 1000.0, 0.1),
		"  (real %.1f, escala del nodo %.4f)" % [LARGO_REAL * 1000.0, escala_mundo])
	if absf(largo - LARGO_REAL) > TOLERANCIA:
		fallos += 1
		print("FALLO: la pistola no esta en escala real en el mundo")

	if arma.muzzle == null or arma.ejection_port == null \
			or arma.sight_rear == null or arma.sight_front == null \
			or arma.frame == null or arma.slide == null or arma.magazine == null:
		fallos += 1
		print("FALLO: falta una pieza o un punto que el juego usa")
	# Trigger y Barrel son opcionales: el asset actual no los trae.
	print("trigger ", "si" if arma.trigger != null else "NO (opcional)",
		"  barrel ", "si" if arma.barrel != null else "NO (opcional)")

	var adelante: Vector3 = (arma.sight_front.global_position - arma.sight_rear.global_position).normalized()
	var arriba: Vector3 = arma.slide.global_transform.basis.y.normalized()
	var salida: Vector3 = arma.magazine_out_axis()
	print("mira trasera->delantera mm ",
		snappedf(arma.sight_rear.global_position.distance_to(arma.sight_front.global_position) * 1000.0, 0.1))
	print("eje de salida del cargador ", salida.snapped(Vector3(0.01, 0.01, 0.01)),
		"  abajo=", snappedf(salida.dot(arriba), 0.01), "  avance=", snappedf(absf(salida.dot(adelante)), 0.01))
	if salida.dot(arriba) > -0.8 or absf(salida.dot(adelante)) > 0.4:
		fallos += 1
		print("FALLO: el cargador no sale hacia abajo por el brocal")

	# El gatillo gira sobre el pasador: si el eje estuviera mal, la punta se
	# moveria en diagonal o el pasador se iria de sitio.
	if arma.trigger != null:
		var origen: Vector3 = arma.trigger.global_transform.origin
		## Se sigue el MISMO vertice en las dos poses. Buscar "el mas lejano"
		## cada vez no vale: la punta es un filo y el argmax salta de un vertice
		## a otro, que es como esta comprobacion midio 0,6 mm de 5 mm.
		var testigo: Array = _testigo(arma.trigger)
		arma.set_trigger(0.0)
		var punta_suelto := _sigue(testigo)
		arma.set_trigger(1.0)
		var punta_fondo := _sigue(testigo)
		## Mundo ya viene en metros: no se vuelve a escalar.
		var recorrido_gatillo: float = punta_suelto.distance_to(punta_fondo)
		var pasador: float = origen.distance_to(arma.trigger.global_transform.origin)
		print("gatillo mm ", snappedf(recorrido_gatillo * 1000.0, 0.1),
			"  (recorrido real %.1f)  pasador movido mm %.2f" % [
				arma.TRIGGER_TRAVEL * 1000.0, pasador * 1000.0])
		if absf(recorrido_gatillo - arma.TRIGGER_TRAVEL) > 0.0012 or pasador > 0.0002:
			fallos += 1
			print("FALLO: el gatillo no gira sobre su pasador")
		arma.set_trigger(0.0)

	# El cañon cae al abrirse el arma: si subiera, el giro esta al reves.
	if arma.barrel != null:
		## Se mide la BOCA del cañon, no el nodo `Muzzle`: ese cuelga de la
		## corredera y se mueve con ella, asi que no dice nada del cañon.
		var boca_testigo: Array = _testigo(arma.barrel)
		arma.set_slide(0.0)
		var boca_suelto := _sigue(boca_testigo)
		arma.set_slide(1.0)
		var boca_abierto := _sigue(boca_testigo)
		arma.set_slide(0.0)
		print("cañon al abrir mm ", snappedf((boca_suelto - boca_abierto).dot(arriba) * 1000.0, 0.1),
			"  (baja si es positivo)")
		if (boca_suelto - boca_abierto).dot(arriba) < 0.0005:
			fallos += 1
			print("FALLO: el cañon no cae al abrir la corredera")

	# El gatillo NO puede salir con el cargador. Hasta ahora los dos vivian en el
	# mismo nodo del autor, asi que al expulsar el cargador se iba el gatillo.
	if arma.trigger != null and arma.magazine != null:
		var gatillo_antes: Vector3 = arma.trigger.global_transform.origin
		arma.set_magazine_offset(1.0)
		var gatillo_fuera: Vector3 = arma.trigger.global_transform.origin
		arma.set_magazine_offset(0.0)
		print("gatillo quieto con el cargador fuera mm ",
			snappedf(gatillo_antes.distance_to(gatillo_fuera) * 1000.0, 2))
		if gatillo_antes.distance_to(gatillo_fuera) > 0.0005:
			fallos += 1
			print("FALLO: el gatillo se va con el cargador")

	var recorrido: float = (arma.corredera / arma.escala) * escala_mundo
	print("recorrido de corredera mm ", snappedf(recorrido * 1000.0, 0.1),
		"  (real %.1f)" % (CORREDERA_REAL * 1000.0))
	if absf(recorrido - CORREDERA_REAL) > TOLERANCIA * 0.5:
		fallos += 1
		print("FALLO: la corredera no recorre la distancia real")

	if fallos == 0:
		print("OK: invariantes del arma")
	else:
		print("FALLOS: ", fallos)
	get_tree().quit(1 if fallos > 0 else 0)


## Vertice testigo de la pieza: el mas lejano a su origen (la punta del
## gatillo, la boca del cañon). Devuelve [malla, indice] para poder seguir ESE
## vertice en otra pose.
func _testigo(pieza: Node3D) -> Array:
	var testigo: Array = []
	var radio := 0.0
	var origen: Vector3 = pieza.global_transform.origin
	var pila: Array = [pieza]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var malla: MeshInstance3D = n as MeshInstance3D
			for s in range(malla.mesh.get_surface_count()):
				var vertices: PackedVector3Array = malla.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for i in range(vertices.size()):
					var d: float = (malla.global_transform * vertices[i]).distance_to(origen)
					if d > radio:
						radio = d
						testigo = [malla, i]
		for c in n.get_children():
			pila.append(c)
	return testigo


## Posicion en mundo del vertice testigo.
func _sigue(testigo: Array) -> Vector3:
	if testigo.is_empty():
		return Vector3.ZERO
	var malla: MeshInstance3D = testigo[0]
	var vertices: PackedVector3Array = malla.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return malla.global_transform * vertices[testigo[1]]


## Largo de la pistola en unidades del PROPIO arma (sin rotaciones de padre).


func _largo_local(raiz: Node3D) -> float:
	return maxf(_caja_local(raiz, false).size.x, maxf(_caja_local(raiz, false).size.y, _caja_local(raiz, false).size.z))


## Caja del arma en su propio espacio. Con `detalle` imprime la caja de cada
## malla: si el largo sale mal, aqui se ve QUE pieza se esta saliendo.
func _caja_local(raiz: Node3D, detalle: bool) -> AABB:
	var caja := AABB()
	var primero := true
	var inversa := raiz.global_transform.affine_inverse()
	var pila: Array = [raiz]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local: AABB = (inversa * (n as Node3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
			if detalle:
				print("  pieza ", (n as Node3D).name, "  caja ",
					local.size.snapped(Vector3(0.001, 0.001, 0.001)),
					"  desde ", local.position.snapped(Vector3(0.001, 0.001, 0.001)))
			caja = local if primero else caja.merge(local)
			primero = false
		for c in n.get_children():
			pila.append(c)
	if detalle:
		print("  caja total ", caja.size.snapped(Vector3(0.001, 0.001, 0.001)))
	return caja
