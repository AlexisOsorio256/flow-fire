extends Node
## Mide la velocidad del juego real. Imprime ms por frame: media, peor 1% y
## peor 5%. Un solo numero no dice nada; el peor 1% es el que se siente.

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().create_timer(3.0).timeout   # deja asentar carga e importacion
	var ms: Array[float] = []
	for i in range(240):
		await get_tree().process_frame
		ms.append(get_process_delta_time() * 1000.0)
		if i == 120:
			var w = (main.get_node("Player") as Node).get("weapon")
			if w != null:
				w.force_fire_once()
	ms.sort()
	var total := 0.0
	for v in ms:
		total += v
	var media := total / ms.size()
	var peor1 := ms[int(ms.size() * 0.99)]
	var peor5 := ms[int(ms.size() * 0.95)]
	print("FPS   media %.1f ms (%.0f fps) | peor5 %.1f ms | peor1 %.1f ms | max %.1f ms" % [
		media, 1000.0 / media, peor5, peor1, ms[ms.size() - 1]])
	get_tree().quit()
