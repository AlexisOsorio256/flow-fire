extends Node
## INVARIANTES DEL ARMA, sin abrir el editor ni mirar la pantalla.
##
##   godot --headless --path . tools/check_weapon.tscn
##
## Comprueba lo que el ojo no mide: que la pistola este en METROS REALES en el
## mundo (187 mm de largo), que existan las piezas que el juego mueve y que el
## cargador viaje hacia abajo en el espacio del arma. Si algo falla, imprime
## FALLO y sale con codigo 1.

const LARGO_REAL := 0.187
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

	var recorrido: float = (arma.corredera / arma.escala) * escala_mundo
	print("recorrido de corredera mm ", snappedf(recorrido * 1000.0, 0.1),
		"  (real %.1f)" % (CORREDERA_REAL * 1000.0))
	if absf(recorrido - CORREDERA_REAL) > TOLERANCIA * 0.5:
		fallos += 1
		print("FALLO: la corredera no recorre la distancia real")

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

	if fallos == 0:
		print("OK: invariantes del arma")
	else:
		print("FALLOS: ", fallos)
	get_tree().quit(1 if fallos > 0 else 0)


## Largo de la pistola en unidades del PROPIO arma (sin rotaciones de padre).
func _largo_local(raiz: Node3D) -> float:
	var caja := AABB()
	var primero := true
	var inversa := raiz.global_transform.affine_inverse()
	var pila: Array = [raiz]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local: AABB = (inversa * (n as Node3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
			caja = local if primero else caja.merge(local)
			primero = false
		for c in n.get_children():
			pila.append(c)
	return maxf(caja.size.x, maxf(caja.size.y, caja.size.z))
