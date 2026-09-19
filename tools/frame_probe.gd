extends Node
## ENCUADRE REAL, en numeros, para el banco de Blender.
##
##   godot --headless --path . tools/frame_probe.tscn
##
## Escribe un JSON con, para cada estado del viewmodel (cadera, ADS, recarga,
## recarga en seco, inspeccion y pico de retroceso), la transformacion de cada
## nodo de la cadena EN ESPACIO DE CAMARA:
##
##   camera -> WeaponRig -> Viewmodel -> PoseRoot -> BodyGive -> WeaponGrip
##           -> WeaponSocket -> Weapon
##
## POR QUE EXISTE: el banco de Blender tiene que mirar lo mismo que el juego. Si
## el encuadre de Blender se recalcula a ojo a partir de las constantes, el banco
## certifica una pose que el juego nunca dibuja. Estos numeros salen del runtime
## de verdad, asi que `tools/bench_arms.py` no adivina: coloca.
##
## Monta la MISMA cadena que `Player._build_weapon` (rig dentro de la camara, no
## solo el viewmodel): pedirle la mecanica al viewmodel no funciona, porque
## `GlockViewmodel.weapon` es el arbol de piezas (`GlockWeapon`), no `Glock.gd`.

const OUT_DEFAULT := "captures/arms_bench/frame.json"
const RAD2DEG := 180.0 / PI
const RIG_POS := Vector3(0.0, -0.185, -0.345)

## Estados con los que se mira el arma. `reload_at` / `inspect_at` avanzan la
## mecanica de verdad a pasos de 1/240 s hasta ese hito.
const STATES := [
	{"name": "hip"},
	{"name": "ads", "aim": 1.0},
	{"name": "reload_out", "reload_at": 0.28},
	{"name": "reload_in", "reload_at": 1.02},
	{"name": "reload_seat", "reload_at": 1.40},
	{"name": "reload_empty_slide", "reload_at": 1.72, "empty": true},
	{"name": "inspect", "inspect_at": 0.55},
	{"name": "fire_peak", "fire": true},
	{"name": "sprint", "sprint": 1.0},
]

var _out := OUT_DEFAULT
var _camera: Camera3D
var _rig: Node3D
var _mech: Node3D
var _vm: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=")
		if kv.size() == 2 and kv[0] == "--out":
			_out = kv[1]
	_build()
	if _mech == null:
		get_tree().quit(1)
		return
	var report := {
		"camera": {"fov_deg": _camera.fov, "near": _camera.near, "rig_pos": _v3(RIG_POS), "rig": _rig_path()},
		"states": {},
	}
	for state in STATES:
		# UN ARMA NUEVA POR ESTADO. Reutilizarla contamina: una recarga sin
		# terminar bloquea `inspect_weapon()` y `force_fire_once()`, y los
		# estados salian con la pose del anterior (el pico de retroceso daba
		# cero). El probe mide estados independientes, asi que los monta
		# independientes.
		_rebuild()
		_drive(state)
		report["states"][state["name"]] = _snapshot()
	report["ads_solved"] = {
		"offset": _v3(_vm.get("ads_offset")),
		"rot_deg": _v3(_vm.get("ads_rot") * RAD2DEG),
	}
	var dir := _out.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f == null:
		print("PROBE FALLO: no se pudo escribir ", _out)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("PROBE escrito ", _out, " estados=", STATES.size())
	get_tree().quit(0)


## La misma cadena que el juego: camara -> WeaponRig -> Glock -> Viewmodel.
func _build() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 82.0
	_camera.near = 0.04
	add_child(_camera)
	_rig = Node3D.new()
	_rig.name = "WeaponRig"
	_rig.position = RIG_POS
	_camera.add_child(_rig)
	_mech = preload("res://scripts/Glock.gd").new()
	_mech.name = "Glock"
	# `Glock._ready` ya monta el viewmodel: no se monta dos veces (el segundo
	# montaje duplicaba el arbol de piezas y ensuciaba todas las medidas).
	_rig.add_child(_mech)
	_vm = _mech.get("viewmodel")
	if _vm == null or _vm.get("weapon") == null:
		print("PROBE FALLO: el arma no monto")
		_mech = null
		return
	_mech.setup(_camera)
	_camera.force_update_transform()
	_vm.solve_ads()


## Descarta el arma y monta otra limpia en el mismo rig.
func _rebuild() -> void:
	_rig.remove_child(_mech)
	_mech.queue_free()
	_mech = preload("res://scripts/Glock.gd").new()
	_mech.name = "Glock"
	_rig.add_child(_mech)
	_vm = _mech.get("viewmodel")
	_mech.setup(_camera)
	_camera.force_update_transform()


func _rig_path() -> Array:
	return ["Camera", "WeaponRig"]


func _drive(state: Dictionary) -> void:
	if state.has("reload_at"):
		var empty: bool = state.get("empty", false)
		_mech.set("mag", 0 if empty else 10)
		_mech.set("chamber", 0 if empty else 1)
		_mech.set("slide_locked", empty)
		_mech.set("slide_pos", 0.039 if empty else 0.0)
		_mech.set("slide_vel", 0.0)
		_mech.start_reload(15)
		_advance("_update_reload", "reload_elapsed", float(state["reload_at"]))
	if state.has("inspect_at"):
		_mech.inspect_weapon()
		_advance("_update_inspect", "inspect_elapsed", float(state["inspect_at"]))
	if state.get("fire", false):
		_mech.force_fire_once()
		for _i in range(5):
			_mech.call("_process", 1.0 / 60.0)
	_mech.set_motion(0.0, Vector2.ZERO, Vector2.ZERO)
	_mech.set_aim(state.get("aim", 0.0) > 0.5)
	_mech.set_sprint(state.get("sprint", 0.0) > 0.5)
	# Los blends de aim/sprint los mueve `_update_aim` con exponenciales: se
	# fuerza el valor final para que la pose del probe sea la de regimen.
	_mech.set("aim_blend", state.get("aim", 0.0))
	_mech.set("sprint_blend", state.get("sprint", 0.0))
	var pose := float(_mech.get("reload_pose_blend"))
	var inspect_pose := float(_mech.get("inspect_pose_blend"))
	_vm.set_pose_inputs(float(state.get("aim", 0.0)), float(state.get("sprint", 0.0)), 0.0,
		Vector2.ZERO, Vector2.ZERO, clampf(pose, -0.3, 1.0), clampf(inspect_pose, -0.3, 1.0))
	_vm.update(0.0)
	_camera.force_update_transform()
	(_vm as Node3D).force_update_transform()


## Avanza la MECANICA por su propio `_process`, que es la ruta real: llamar a
## `_update_reload` a mano saltaba el resto del frame y dejaba la pose a medias.
func _advance(_method: String, field: String, target: float) -> void:
	var guard := 0
	while float(_mech.get(field)) < target - 1e-4 and guard < 4000:
		_mech.call("_process", 1.0 / 240.0)
		guard += 1


func _snapshot() -> Dictionary:
	var out := {}
	for path in [
		"PoseRoot", "PoseRoot/BodyGive", "PoseRoot/BodyGive/WeaponGrip",
		"PoseRoot/BodyGive/WeaponGrip/WeaponSocket",
	]:
		var n := _vm.get_node_or_null(path)
		if n != null:
			out[path] = _xform(n)
	var weapon_node := _vm.get_node_or_null("PoseRoot/BodyGive/WeaponGrip/WeaponSocket/Weapon")
	if weapon_node != null:
		out["Weapon"] = _xform(weapon_node)
		for part in ["grip", "muzzle", "sight_rear", "sight_front", "ejection_port"]:
			var p = weapon_node.get(part)
			if p != null:
				out[part] = _xform(p)
	out["muzzle_world_forward"] = _v3(-(_vm.get("muzzle") as Node3D).global_transform.basis.z)
	## Estado mecanico en el hito: sin esto, una captura del banco no se puede
	## cruzar con la mecanica ("¿la corredera estaba abierta en ESTE frame?").
	out["mechanic"] = {
		"slide_mm": snappedf(float(_mech.get("slide_pos")) * 1000.0, 0.01),
		"slide_locked": bool(_mech.get("slide_locked")),
		"chamber": int(_mech.get("chamber")),
		"mag": int(_mech.get("mag")),
		"reloading": bool(_mech.get("reloading")),
		"inspecting": bool(_mech.get("inspecting")),
		"reload_elapsed": snappedf(float(_mech.get("reload_elapsed")), 0.001),
		"inspect_elapsed": snappedf(float(_mech.get("inspect_elapsed")), 0.001),
	}
	var rec = _mech.get("recoil")
	out["recoil"] = {
		"pos": _v3(rec.get("pos")),
		"rot_deg": _v3(rec.get("rot") * RAD2DEG),
		"give_pos": _v3(rec.get("give_pos")),
		"give_rot_deg": _v3(rec.get("give_rot") * RAD2DEG),
	}
	return out


func _xform(node: Node) -> Dictionary:
	var t: Transform3D = _camera.global_transform.affine_inverse() * (node as Node3D).global_transform
	return {
		"origin": _v3(t.origin),
		"basis": [_v3(t.basis.x), _v3(t.basis.y), _v3(t.basis.z)],
	}


func _v3(v: Variant) -> Array:
	var vec := v as Vector3
	return [snappedf(vec.x, 0.000001), snappedf(vec.y, 0.000001), snappedf(vec.z, 0.000001)]
