extends Node
## ReviewCapture: graba UNA accion del juego real a frames PNG.
##
## No es un test, no mide nada, no da veredictos: deja el juego correr,
## dispara la accion y guarda lo que se ve. La hoja de contacto la compone
## `tools/review_contact_sheet.py` a partir de estos frames.
##
## Uso (lo invoca review_contact_sheet.py, no a mano):
##   godot4 --path . --audio-driver Dummy --resolution 960x540 \
##     tools/review_capture.tscn -- --action fire --out /tmp/x --warmup 40 --total 50

var action := "fire"
var out_dir := "/tmp/review_frames"
var warmup := 40
var total := 50
var time_scale := 1.0

var _frame := 0
var _t0 := 0
var _game: Node = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"--action":
				action = kv[1]
			"--out":
				out_dir = kv[1]
			"--warmup":
				warmup = int(kv[1])
			"--total":
				total = int(kv[1])
			"--time-scale":
				time_scale = float(kv[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.time_scale = time_scale
	_game = load("res://scenes/Main.tscn").instantiate()
	add_child(_game)


func _player_weapon() -> Node:
	var player := _game.get_node_or_null("Player")
	if player == null:
		return null
	return (player as Node).get("weapon")


func _trigger() -> void:
	_t0 = Time.get_ticks_msec()
	var weapon := _player_weapon()
	if weapon == null:
		return
	match action:
		"fire":
			weapon.force_fire_once()
		"reload":
			weapon.set("mag", 10)
			weapon.start_reload()
		"reload_empty":
			weapon.set("mag", 0)
			weapon.set("chamber", 0)
			weapon.set("reserve", 60)
			weapon.set("slide_locked", true)
			weapon.set("slide_pos", 0.039)
			weapon.start_reload()
		"inspect":
			weapon.inspect_weapon()
		"idle":
			pass


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == warmup:
		_trigger()
	if _frame >= warmup and (_frame - warmup) < total:
		var img := get_viewport().get_texture().get_image()
		# Etiqueta en ms DE JUEGO (con camara lenta, el reloj real miente).
		var ms := int((Time.get_ticks_msec() - _t0) * time_scale)
		img.save_png("%s/f_%04d_%dms.png" % [out_dir, _frame - warmup, ms])
	elif _frame >= warmup + total:
		get_tree().quit()
