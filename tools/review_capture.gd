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
var _burst_left := 0
var _burst_gap := 3

var _frame := 0
var _t0 := 0
var _game: Node = null
var _shots_fired := 0
var _shots_tried := 0


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
	await get_tree().process_frame
	var _w := _player_weapon()
	if _w != null:
		_w.shot_fired.connect(_on_shot_fired)


func _on_shot_fired() -> void:
	_shots_fired += 1


func _player_weapon() -> Node:
	var player := _game.get_node_or_null("Player")
	if player == null:
		return null
	return (player as Node).get("weapon")


func _trigger() -> void:
	_t0 = Time.get_ticks_msec()
	_shots_tried += 1
	var weapon := _player_weapon()
	if weapon == null:
		return
	match action:
		"fire":
			weapon.force_fire_once()
		"burst":
			weapon.force_fire_once()
			_burst_left = 3
		"pen":
			# El teletransporte va 2 frames ANTES del disparo: el global_transform
			# tiene que asentarse o la bala nace de la posicion anterior.
			weapon.force_fire_once()
			_burst_left = 1
			_burst_gap = 14
		"ads":
			# Apunta, deja asentar el blend y dispara dos veces con la mira.
			weapon.set_aim(true)
			_burst_left = 2
			_burst_gap = 8
		"crate":
			# Delante de las cajas: dos tiros para ver empuje, vuelco y
			# agujeros viajando con la caja.
			weapon.force_fire_once()
			_burst_left = 1
			_burst_gap = 14
		"steel":
			# Delante del acero: chispa + luz + clang + oscilacion del plato.
			weapon.force_fire_once()
			_burst_left = 1
			_burst_gap = 14
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
			# Como pulsar F con el arma cerrada: el gesto real incluye el
			# tiron a 0,30 s (la corredera salta atras) y la suelta a 1,20 s.
			weapon.inspect_weapon()
		"idle":
			pass


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == warmup - 4 and (action == "pen" or action == "crate" or action == "steel"):
		var player := _game.get_node_or_null("Player")
		if player != null:
			if action == "pen":
				# Delante del blanco de papel x=0: blanco sobre fondo, oscila al
				# recibir, y el papel se atraviesa (entrada + salida + paso).
				(player as Node3D).global_position = Vector3(0.0, 0.05, -16.5)
			elif action == "steel":
				(player as Node3D).global_position = Vector3(0.0, 0.05, -24.0)
			else:
				# Ligeramente a un lado de las cajas: se ven junto al arma y
				# el tiro les da de lleno (centradas quedarian tras el arma).
				(player as Node3D).global_position = Vector3(4.7, 0.05, -7.0)
				# Pica la vista: a 2.5 m el tiro de pie pasa por encima de
				# las cajas si no se apunta hacia abajo, como haria un tirador.
				player.set("pitch", -0.12)
				player.set("pitch_target", -0.12)
			player.set("yaw", 0.0)
			player.set("yaw_target", 0.0)
	if _frame == warmup:
		_trigger()
	if _frame >= warmup and (_frame - warmup) < total:
		# Rafaga: disparos extra separados _burst_gap frames (~90 ms de juego).
		# En ads el primero cae con el blend ya asentado (el del trigger no
		# existe: (frame-warmup)>0 lo excluye en el instante cero).
		if (action == "burst" or action == "pen" or action == "ads" or action == "crate" or action == "steel") and _burst_left > 0 and (_frame - warmup) % _burst_gap == 0:
			var weapon := _player_weapon()
			if weapon != null and (_frame - warmup) > 0:
				_shots_tried += 1
				weapon.force_fire_once()
				_burst_left -= 1
		var img := get_viewport().get_texture().get_image()
		# Etiqueta en ms DE JUEGO (con camara lenta, el reloj real miente).
		var ms := int((Time.get_ticks_msec() - _t0) * time_scale)
		img.save_png("%s/f_%04d_%dms.png" % [out_dir, _frame - warmup, ms])
	elif _frame >= warmup + total:
		print("REVIEW disparos intentados=", _shots_tried, " ocurridos=", _shots_fired)
		get_tree().quit()
