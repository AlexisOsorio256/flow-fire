extends Node
## MIDE los dos instantes del clip de recarga en los que cambia de mano el
## cargador, y los imprime como constantes para `Glock.gd`.
##
##   godot4 --path . --resolution 960x540 tools/check_reload.tscn -- --empty
##
## La mano izquierda es la que recarga: se mide, frame a frame, la distancia
## entre su hueso y el brocal del arma. El PRIMER minimo local es la mano
## agotando el cargador que sale; el ULTIMO es la mano devolviendolo al brocal.
## El clip decide: si el clip cambia, esta herramienta vuelve a medirlos.

var _t: Array[float] = []
var _d: Array[float] = []


func _ready() -> void:
	var vacio: bool = "--empty" in OS.get_cmdline_user_args()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var w: Node = main.get_node("Player").get("weapon")
	var vm = w.get("viewmodel")
	var cap: int = w.get("MAG_SIZE")
	w.set("mag", 0 if vacio else maxi(1, cap / 2))
	w.set("chamber", 0 if vacio else 1)
	print("CLIP ", "Reload_Empty" if vacio else "Reload", "  (capacidad ", cap, ")")
	w.start_reload()
	var fotogramas := 0
	while fotogramas < 400:
		await get_tree().process_frame
		fotogramas += 1
		var muneca: Variant = _punto_mano(vm)
		var brocal: Variant = _punto_brocal(vm)
		if muneca == null or brocal == null:
			break
		var t: float = w.get("reload_elapsed")
		var d: float = (muneca as Vector3).distance_to(brocal as Vector3)
		_t.append(t)
		_d.append(d)
		if not bool(w.get("reloading")):
			break

	var mins: Array = []
	for i in range(2, _d.size() - 2):
		if _d[i] < _d[i - 1] and _d[i] < _d[i + 1] and _d[i] <= _d[i - 2] and _d[i] <= _d[i + 2]:
			mins.append(i)
	if mins.is_empty():
		print("SIN MINIMOS: revisa el clip")
		get_tree().quit()
		return
	var sale: int = mins[0]
	var entra: int = mins[mins.size() - 1]
	print("MINIMOS locales: ", mins.size(), " en t=", mins.map(func(i): return snappedf(_t[i], 0.01)))
	print("  el mas cercano: t=%.2f  d=%.3f" % [_t[_d.find(_d.min())], _d.min()])
	print("CONSTANTE %s_MAG_OUT_T := %.2f   # distancia %.3f" % [
		"RELOAD_EMPTY" if vacio else "RELOAD", _t[sale], _d[sale]])
	print("CONSTANTE %s_MAG_IN_T := %.2f   # distancia %.3f" % [
		"RELOAD_EMPTY" if vacio else "RELOAD", _t[entra], _d[entra]])
	for i in range(_d.size()):
		print("CURVA %6.3f %.4f" % [_t[i], _d[i]])
	get_tree().quit()


func _punto_mano(vm) -> Variant:
	var sk = vm.arms_skeleton
	var h: int = vm.hand_bone_index()
	if sk == null or h < 0:
		return null
	sk.force_update_all_bone_transforms()
	return sk.global_transform * sk.get_bone_global_pose(h).origin


func _punto_brocal(vm) -> Variant:
	if vm.weapon == null:
		return null
	return vm.weapon.global_transform * vm.weapon.magazine_rest
