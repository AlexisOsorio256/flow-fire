extends Node
## Shot: captura el juego REAL a frames PNG.
##
## Es la herramienta de PERCEPCION de esta pasada: en vez de discutir si algo
## "esta bien", deja el juego correr, dispara la accion y guarda lo que se ve.
## Lo que no sale en una captura no existe.
##
## Uso (lo orquesta tools/captura.sh):
##   godot4 --path . --resolution 1920x1080 tools/shot.tscn -- \
##     --action=ads --out=captures/shot/ads --warmup=30 --total=8
##
## OJO: los argumentos van en forma --clave=valor. Godot parte
## `OS.get_cmdline_user_args()` por espacios, asi que "--out X" llega como dos
## elementos y el parser lo ignora EN SILENCIO (paso, y las capturas acabaron
## todas en el directorio por defecto sin avisar).

var action := "idle"
var out_dir := "/tmp/shot"
var warmup := 30
var total := 8
var time_scale := 1.0
var frame_stride := 1
## Frames de mecanica a simular ANTES de la accion.
var advance := 0

var _frame := 0
## Tiempo de JUEGO acumulado (ms) y el instante de la accion. Las capturas se
## nombran por su offset real desde la accion, no por su indice: con camara lenta
## `Engine.time_scale` cambia cuanto juego cabe en un frame, y el indice miente.
var _game_ms := 0.0
var _action_ms := -1.0
var _game: Node = null
var _player: Node = null
var _weapon: Node = null
var _view: Viewport = null
var _shots := 0


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
			"--stride":
				frame_stride = int(kv[1])
			"--advance":
				advance = int(kv[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.time_scale = time_scale
	_game = load("res://scenes/Main.tscn").instantiate()
	add_child(_game)
	_view = get_viewport()
	await get_tree().process_frame
	_player = _game.get_node_or_null("Player")
	if _player != null:
		_weapon = _player.get("weapon")
	_place()


## Encuadres: cada accion lleva al jugador donde esa accion se ve.
## La variable `p` solo existe AQUI. Meter ramas de encuadre en `_trigger()` (que
## no tiene jugador) fue un error de sintaxis que dejo el juego sin arrancar.
func _place() -> void:
	if _player == null:
		return
	var p := _player as Node3D
	match action:
		"steel":
			p.global_position = Vector3(0.0, 0.05, -24.0)
			_aim(0.0, -0.02)
		"wood":
			p.global_position = Vector3(-2.5, 0.05, -9.0)
			_aim(0.0, -0.12)
		"drywall":
			p.global_position = Vector3(8.6, 0.05, -16.0)
			_aim(0.0, -0.18)
		"aluminum":
			# Las latas de pie (World las pone en 6,6 / 0,98 / -11,0). El preset
			# apuntaba a (-1,3, -9,6) hacia las latas del SUELO, pero el muro de
			# tablones esta en (-2,5, -12) y las tapa: la captura "aluminum"
			# ensenaba un impacto en MADERA. La prueba de `thin_shell` se hace
			# contra las latas de pie, que tienen linea de tiro limpia.
			# A 1,5 m de las latas: a 4,5 m la lata son 19 px y el agujero no se
			# lee en la captura, que es justo lo que hay que poder juzgar.
			p.global_position = Vector3(6.6, 0.05, -9.5)
			_aim(0.0, -0.40)
		"crate":
			p.global_position = Vector3(4.7, 0.05, -8.3)
			_aim(0.0, -0.10)
		"wall":
			p.global_position = Vector3(8.6, 0.05, -16.0)
			_aim(0.0, -0.18)
		"table":
			# Delante de la mesa de cargadores, a la distancia de agarre.
			p.global_position = Vector3(1.9, 0.05, -2.6)
			_aim(0.0, -0.34)
		"downrange":
			# Desde el puesto mirando al fondo: es el encuadre de juego real.
			p.global_position = Vector3(2.0, 0.05, 0.5)
			_aim(0.0, -0.02)
		_:
			p.global_position = Vector3(2.0, 0.05, 0.5)
			_aim(0.0, 0.0)


func _aim(yaw: float, pitch: float) -> void:
	_player.set("yaw", yaw)
	_player.set("yaw_target", yaw)
	_player.set("pitch", pitch)
	_player.set("pitch_target", pitch)


func _process(delta: float) -> void:
	_frame += 1
	_game_ms += delta * 1000.0
	if _frame == warmup - 2:
		if advance > 0 and _weapon != null:
			for _i in range(advance):
				_weapon.call("_update_slide", 1.0 / 60.0)
		_trigger()
	if _frame >= warmup and _frame < warmup + total:
		if (_frame - warmup) % frame_stride == 0:
			var offset := _game_ms - (_action_ms if _action_ms >= 0.0 else _game_ms)
			_view.get_texture().get_image().save_png(
				"%s/f_%05dms.png" % [out_dir, int(round(offset))])
	elif _frame >= warmup + total:
		print("SHOT action=%s frames=%d disparos=%d dir=%s" % [action, total, _shots, out_dir])
		get_tree().quit()


func _trigger() -> void:
	if _weapon == null:
		return
	_action_ms = _game_ms
	match action:
		"fire", "ads_fire", "steel", "wood", "drywall", "aluminum", "crate":
			if action.begins_with("ads"):
				_weapon.set_aim(true)
			_weapon.force_fire_once()
			_shots += 1
		"ads":
			_weapon.set_aim(true)
		"burst":
			_weapon.press_trigger()
		"empty":
			# ULTIMO disparo: recamara llena y cargador a cero. La mecanica real
			# hace el resto (la corredera no vuelve a bateria porque no hay
			# cartucho que alimentar).
			_weapon.set("mag", 0)
			_weapon.set("chamber", 1)
			_weapon.set("slide_locked", false)
			_weapon.set("slide_pos", 0.0)
			_weapon.set("slide_vel", 0.0)
			_weapon.force_fire_once()
			_shots += 1
		"reload":
			_weapon.set("mag", 10)
			_weapon.start_reload(15)
		"reload_empty":
			_weapon.set("mag", 0)
			_weapon.set("chamber", 0)
			_weapon.set("slide_locked", true)
			_weapon.set("slide_pos", 0.039)
			_weapon.start_reload(15)
		"inspect":
			_weapon.inspect_weapon()
		"table":
			_player.call("try_reload_from_table")
		_:
			pass
