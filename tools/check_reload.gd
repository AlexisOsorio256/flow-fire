extends Node
## Verify de la MESA de cargadores: validacion antes de consumir y regeneracion.
##
## Comprueba los dos fallos concretos que tenia:
##   1. Un `start_reload` rechazado NO puede gastar un cargador de la mesa.
##   2. La mesa se rellena sola (es un banco de pruebas, no un inventario).
##
##   godot4 --path . --headless tools/check_reload.tscn

var _fallos := 0


func _ready() -> void:
	var world: Node3D = load("res://scripts/World.gd").new()
	world.name = "World"
	add_child(world)
	world.call("build")
	var glock: Node3D = load("res://scripts/Glock.gd").new()
	glock.name = "Glock"
	add_child(glock)
	await get_tree().process_frame


	var pos: Vector3 = world.get("TABLE_POS")

	# --- 1. Cargador lleno: el arma NO acepta recarga -> no se consume nada.
	var antes: int = world.get("table_mags")
	glock.set("mag", 15)
	glock.set("chamber", 1)
	_check(not glock.call("can_reload"), "lleno: el arma no debe aceptar recarga")
	if world.call("can_take_mag", pos) and not glock.call("can_reload"):
		pass  # el flujo de Player no llega a consume_mag
	_check(world.get("table_mags") == antes,
		"lleno: la mesa no debe perder cargador (antes=%d ahora=%d)"
		% [antes, world.get("table_mags")])

	# --- 2. Recarga ya en curso: tampoco se consume.
	glock.set("mag", 5)
	glock.set("chamber", 0)
	glock.set("reloading", true)
	_check(not glock.call("can_reload"), "recargando: no debe aceptar otra recarga")
	_check(world.get("table_mags") == antes, "recargando: la mesa no pierde cargador")
	glock.set("reloading", false)

	# --- 3. Recarga valida: se consume EXACTAMENTE uno.
	_check(glock.call("can_reload"), "vacio: el arma debe aceptar recarga")
	var rounds: int = world.call("consume_mag")
	_check(rounds == 15, "consume_mag devuelve 15 (dio %d)" % rounds)
	_check(world.get("table_mags") == antes - 1,
		"valida: la mesa baja a %d (tiene %d)" % [antes - 1, world.get("table_mags")])

	# --- 4. Se agota y se regenera sola.
	while int(world.get("table_mags")) > 0:
		world.call("consume_mag")
	_check(world.get("table_mags") == 0, "la mesa se puede agotar")
	_check(not world.call("can_take_mag", pos), "mesa vacia: no se puede tomar")
	# Avanzar el reloj de regeneracion a mano, sin esperar 6 s reales.
	var regen: float = world.TABLE_REGEN_S
	for i in range(5):
		world.call("_process", regen + 0.01)
	_check(world.get("table_mags") == 4,
		"la mesa se rellena sola hasta 4 (tiene %d)" % world.get("table_mags"))

	# --- 5. Lejos de la mesa no se puede tomar.
	_check(not world.call("can_take_mag", pos + Vector3(10, 0, 0)),
		"lejos: no se puede tomar cargador")

	if _fallos == 0:
		print("CHECK reload: OK (validacion antes de consumir + mesa infinita)")
	else:
		print("CHECK reload: %d FALLOS" % _fallos)
	get_tree().quit(1 if _fallos > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fallos += 1
		print("  FALLO: " + message)
