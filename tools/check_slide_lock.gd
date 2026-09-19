extends Node
## Verify del BLOQUEO DE CORREDERA: tiene que ser VISIBLE, no solo correcto.
##
## El estado interno puede estar bien y el usuario no ver nada. Aqui se
## comprueba las dos cosas: que la corredera se queda atras 39 mm, y que el
## hueco de la ventana de expulsión es el que corresponde (que es lo que el ojo
## usa para leer "esta bloqueada").
##
##   godot4 --path . --headless tools/check_slide_lock.tscn

var _fallos := 0


func _ready() -> void:
	var glock: Node3D = load("res://scripts/Glock.gd").new()
	glock.name = "Glock"
	add_child(glock)
	await get_tree().process_frame
	await get_tree().process_frame

	var travel: float = glock.get("_travel")
	var viewmodel = glock.get("viewmodel")
	_check(viewmodel != null and viewmodel.weapon != null, "el arma monto")
	var weapon = viewmodel.weapon

	# ULTIMO disparo: recamara llena, cargador a cero.
	glock.set("mag", 0)
	glock.set("chamber", 1)
	glock.set("slide_locked", false)
	glock.set("slide_pos", 0.0)
	glock.set("slide_vel", 0.0)
	glock.call("force_fire_once")
	_check(glock.get("chamber") == 0, "el ultimo disparo vacia la recamara")

	# Dejar correr la mecanica hasta que se asiente (la corredera tarda ~70 ms).
	for i in range(180):
		glock.call("_update_slide", 1.0 / 120.0)
		glock.call("_process", 1.0 / 120.0)

	var locked: bool = glock.get("slide_locked")
	var pos: float = glock.get("slide_pos")
	_check(locked, "la corredera queda BLOQUEADA (slide_locked=true)")
	_check(absf(pos - travel) < 0.0005,
		"la corredera esta a fondo: %.1f mm de %.1f mm" % [pos * 1000.0, travel * 1000.0])

	# VISIBLE: la corredera tiene que estar desplazada de verdad en el arma.
	var slide_offset: Vector3 = weapon.slide.position - Vector3.ZERO
	# El recorrido se mide contra el reposo que guarda el arma.
	var rest: Vector3 = weapon.get("_slide_rest")
	var moved: float = (weapon.slide.position - rest).length()
	_check(moved > 0.0385,
		"la corredera esta DIBUJADA a %.1f mm de su reposo (debe ser ~39)"
		% (moved * 1000.0))

	# El cañon cae con la corredera: la boca no puede quedarse a la misma altura.
	var barrel_drop: float = absf(weapon.barrel.rotation.x)
	_check(barrel_drop > 0.01,
		"el canon cae al abrir (giro %.2f grados)" % rad_to_deg(barrel_drop))

	# Y NO vuelve a bateria: otro ciclo completo no debe cambiarla.
	for i in range(240):
		glock.call("_update_slide", 1.0 / 120.0)
	_check(glock.get("slide_locked") and absf(float(glock.get("slide_pos")) - travel) < 0.0005,
		"no vuelve a bateria sin cargador")

	print("CHECK slide_lock: %s (recorrido=%.1f mm, bloqueada=%s)"
		% ["OK" if _fallos == 0 else "%d FALLOS" % _fallos, pos * 1000.0, locked])
	get_tree().quit(1 if _fallos > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fallos += 1
		print("  FALLO: " + message)
