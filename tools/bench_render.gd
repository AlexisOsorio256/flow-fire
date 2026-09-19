extends Node
## BenchRender: mide el RENDER real del juego.
##
## Mide el DELTA REAL entre frames con vsync apagado y max_fps=0: si la GPU
## tarda mas, el delta sube. (La sonda vieja `check_fps.gd`, ya retirada, medía
## TIME_PROCESS de script y por eso no decía nada de la GPU.)
##
## DOS MODOS, Y NO VALEN LO MISMO
## ------------------------------
##   --view=WxH   El juego se dibuja en un SubViewport OFFSCREEN de ese tamano.
##                Mide coste de render puro. OJO: si se corre sobre un display
##                virtual (Xvfb) la "GPU" es llvmpipe y los FPS absolutos NO son
##                los del usuario; solo vale para comparar configuraciones.
##   sin --view   Se dibuja en la ventana. En el display REAL da el numero
##                honesto de esa GPU, pero abre ventana.
##
## La ventana se encoge a 64x64 (el minimo de Godot) y se manda fuera de
## pantalla. Eso NO cambia la resolucion de render cuando se usa --view: la
## confusion entre "ventana pequena" y "render pequeno" ya produjo numeros
## falsos en esta pasada, asi que queda escrito.
##
## Uso:
##   godot4 --path . --resolution 64x64 tools/bench_render.tscn -- \
##     --view=1920x1080 --warmup=40 --frames=120 --tag=base

var warmup := 40
var frames := 120
var tag := "bench"
var out_path := ""
var view_size := Vector2i.ZERO
## `--skin=0` apaga la PIEL del viewmodel (los brazos) sin tocar nada mas. Es la
## unica forma de atribuirle un coste a los brazos: dos pasadas del mismo build,
## misma escena, misma luz, mismo mundo. Comparar contra un numero de otra
## maquina no atribuye nada.
var skin := true

var _samples: Array[float] = []
var _frame := 0
var _game: Node = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"--warmup":
				warmup = int(kv[1])
			"--frames":
				frames = int(kv[1])
			"--tag":
				tag = kv[1]
			"--out":
				out_path = kv[1]
			"--view":
				var parts := kv[1].split("x")
				view_size = Vector2i(int(parts[0]), int(parts[1]))
			"--skin":
				skin = kv[1] != "0"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_size(Vector2i(64, 64))
	DisplayServer.window_set_position(Vector2i(-6000, -6000))

	_game = load("res://scenes/Main.tscn").instantiate()
	if view_size != Vector2i.ZERO:
		var container := SubViewport.new()
		container.size = view_size
		container.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.audio_listener_enable_3d = true
		container.own_world_3d = true
		add_child(container)
		container.add_child(_game)
	else:
		add_child(_game)
	await get_tree().process_frame
	if not skin:
		_set_skin_visible(_game, false)


## Apaga SOLO las mallas que cuelgan del esqueleto de los brazos. Se busca por
## tipo de nodo, no por nombre de escena: si el asset se reexporta con otro
## nombre, la medicion sigue valiendo.
func _set_skin_visible(root: Node, visible: bool) -> void:
	var stack: Array = [root]
	var hidden := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).skin != null:
			(node as MeshInstance3D).visible = visible
			hidden += 1
		for child in node.get_children():
			stack.append(child)
	print("BENCH skin=%s mallas_apagadas=%d" % [str(visible), hidden])


func _process(delta: float) -> void:
	_frame += 1
	if _frame <= warmup:
		return
	if _samples.size() >= frames:
		_report()
		return
	# Delta real entre frames. Con vsync off esto ES el frame time: la CPU espera
	# a que la GPU termine, asi que el coste de render entra aqui.
	_samples.append(delta * 1000.0)


func _stat(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n == 0:
		return {"mean": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0}
	var sum := 0.0
	for v in sorted:
		sum += v
	return {
		"mean": sum / float(n),
		"p50": sorted[int(n * 0.50)],
		"p95": sorted[int(min(n - 1, n * 0.95))],
		"p99": sorted[int(min(n - 1, n * 0.99))],
	}


func _report() -> void:
	var s := _stat(_samples)
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("BENCH tag=%s frames=%d view=%dx%d | frame mean_ms=%.2f p50=%.2f p95=%.2f p99=%.2f | fps_mean=%.1f fps_p95=%.1f | draws=%d prims=%d" % [
		tag, _samples.size(), view_size.x, view_size.y,
		s["mean"], s["p50"], s["p95"], s["p99"],
		1000.0 / maxf(s["mean"], 0.0001), 1000.0 / maxf(s["p95"], 0.0001),
		draws, prims,
	])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			var merged := s.duplicate()
			merged["tag"] = tag
			merged["frames"] = _samples.size()
			merged["samples_ms"] = _samples
			f.store_string(JSON.stringify(merged))
	get_tree().quit()
