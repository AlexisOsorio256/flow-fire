extends Node
## Traza la recarga: donde esta la mano, cuando se agarra el cargador y cuando
## vuelve. Sirve para ver si los eventos caen sobre el gesto.

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var player: Node = main.get_node("Player")
	var w: Node = player.get("weapon")
	var vm = w.get("viewmodel")
	w.set("mag", 8)
	w.start_reload()
	var t := 0.0
	var antes := true
	print("t     mano-brocal  cargador_en_mano")
	for i in range(220):
		await get_tree().process_frame
		t += get_process_delta_time()
		var d: float = w._distancia_mano_brocal()
		var en_mano: bool = vm.magazine_in_hand()
		if en_mano != antes:
			print(">>> CAMBIO en t=%.2f  cargador_en_mano=%s  dist=%.3f" % [t, en_mano, d])
			antes = en_mano
		if i % 12 == 0:
			print("%.2f      %.3f        %s" % [t, d, en_mano])
		if not w.get("reloading"):
			print(">>> FIN recarga t=%.2f  cargador_en_mano=%s" % [t, vm.magazine_in_hand()])
			break
	get_tree().quit()
