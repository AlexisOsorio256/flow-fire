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
# La corredera vuelve a bateria en ~50-70 ms (K=4000, C=80, 39 mm): la rafaga
# separa sus intentos 10 frames (~90 ms de juego a time-scale 0,08) para que los
# 4 sean disparos REALES (lo confirma la linea REVIEW). Con 3 frames (~27 ms) la
# mitad se los tragaba el _can_fire y la hoja mentia.
var _burst_gap := 10

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


# Los intentos se cuentan donde se dispara (inmediato + extras), no en
# acciones sin tiro (ads apunta, recargas e inspect no disparan): antes ads
# decia "intentados=3 ocurridos=2" con solo 2 tiros reales.
func _trigger() -> void:
	_t0 = Time.get_ticks_msec()
	var weapon := _player_weapon()
	if weapon == null:
		return
	match action:
		"fire":
			_shots_tried += 1
			weapon.force_fire_once()
		"burst":
			_shots_tried += 1
			weapon.force_fire_once()
			_burst_left = 3
		"pen":
			# El teletransporte va 2 frames ANTES del disparo: el global_transform
			# tiene que asentarse o la bala nace de la posicion anterior.
			_shots_tried += 1
			weapon.force_fire_once()
			_burst_left = 1
			_burst_gap = 14
		"ads":
			# Apunta y dispara dos veces con la mira ya asentada: el blend
			# (tau ~111 ms) pasa el 97% a ~400 ms de juego; el primer tiro cae
			# a +12 frames y el segundo a +24 (a 35-50 ms de juego por frame
			# van sobrados). Antes a +8 el primero caia al 91% todavia
			# moviendose.
			weapon.set_aim(true)
			_burst_left = 2
			_burst_gap = 12
		"crate":
			# Delante de las cajas: dos tiros para ver empuje y agujeros
			# viajando con la caja.
			_shots_tried += 1
			weapon.force_fire_once()
			_burst_left = 1
			_burst_gap = 14
		"steel":
			# Delante del acero: chispa + luz + clang + oscilacion del plato.
			_shots_tried += 1
			weapon.force_fire_once()
			_burst_left = 1
			_burst_gap = 14
		"wall":
			# Pladur de 12,7 mm: dos tiros para ver entrada + salida + paso
			# (el tabique se atraviesa y la bala sigue).
			_shots_tried += 1
			weapon.force_fire_once()
			_burst_left = 1
			_burst_gap = 14
		"can":
			# Latas del suelo (6,6 cm): se apunta con las miras como haria un
			# tirador; desde cadera el anima no perdona y los tiros se van al
			# suelo. Dos tiros con la mezcla ya asentada, como en ads.
			weapon.set_aim(true)
			_burst_left = 2
			_burst_gap = 12
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
	if _frame == warmup - 4 and (action == "pen" or action == "crate" or action == "steel" or action == "can" or action == "wall"):
		var player := _game.get_node_or_null("Player")
		if player != null:
			if action == "wall":
				# Delante del tabique de x=8.6 (z=-18): a 2 m, al centro del
				# panel (2,6 x 2,4 m: no hay como fallar).
				(player as Node3D).global_position = Vector3(8.6, 0.05, -16.0)
				player.set("pitch", -0.18)
				player.set("pitch_target", -0.18)
			elif action == "pen":
				# Delante del blanco de papel x=0: blanco sobre fondo, oscila al
				# recibir, y el papel se atraviesa (entrada + salida + paso).
				(player as Node3D).global_position = Vector3(0.0, 0.05, -16.5)
			elif action == "steel":
				(player as Node3D).global_position = Vector3(0.0, 0.05, -24.0)
			elif action == "can":
				# A 4 m de las latas del suelo (x=-1.6/-1.4, z=-13.6): las
				# miras van a la chapa y el encuadre respira (a 2 m habia que
				# picar 33 grados y la mira tapaba la lata).
				(player as Node3D).global_position = Vector3(-1.3, 0.05, -9.6)
				player.set("pitch", -0.37)
				player.set("pitch_target", -0.37)
				player.set("yaw", 0.05)
				player.set("yaw_target", 0.05)
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
		if (action == "burst" or action == "pen" or action == "ads" or action == "crate" or action == "steel" or action == "can" or action == "wall") and _burst_left > 0 and (_frame - warmup) % _burst_gap == 0:
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
