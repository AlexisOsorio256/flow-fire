extends Node
## Comprueba orientacion y montaje del arma sin abrir el editor.

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node = main.get_node("Player")
	var w = player.get("weapon")
	var vm = w.get("viewmodel")
	var arma = vm.get("weapon")
	print("--- ARMA ---")
	print("escala ", arma.escala, " capacidad ", arma.capacidad)
	for n in ["frame", "slide", "magazine", "muzzle", "ejection_port", "sight_rear", "sight_front"]:
		var nodo = arma.get(n)
		if nodo == null:
			print("  FALTA ", n)
		else:
			var lp: Vector3 = nodo.position.snapped(Vector3(0.0001, 0.0001, 0.0001))
			var gp: Vector3 = nodo.global_position.snapped(Vector3(0.0001, 0.0001, 0.0001))
			print("  %-14s local %s  mundo %s" % [n, lp, gp])
	var dir: Vector3 = -arma.muzzle.global_transform.basis.z.normalized()
	var cam := player.get_node("Camera") as Camera3D
	var camf := -cam.global_transform.basis.z.normalized()
	print("boca apunta ", dir.snapped(Vector3(0.001, 0.001, 0.001)), " camara ", camf.snapped(Vector3(0.001, 0.001, 0.001)), " dot=", snappedf(dir.dot(camf), 0.001))
	var arriba: Vector3 = arma.slide.global_transform.basis.y.normalized()
	print("alza (Y corredera) ", arriba.snapped(Vector3(0.001, 0.001, 0.001)), " mundo Y ", Vector3.UP)
	print("separacion mira trasera-delantera mm ", snappedf(arma.sight_rear.global_position.distance_to(arma.sight_front.global_position)*1000.0, 0.1))
	print("mano-brocal mm ", snappedf(w._distancia_mano_brocal()*1000.0, 0.1))
	get_tree().quit()
