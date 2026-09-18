extends Node
## Inspector del ASSET a PNG (poses fijas, sin mecanica). No valida acciones:
## no ejecuta ciclo, timings, flash, audio ni recarga real. Para acciones usar
## review_capture con señales reales y conteo de disparos.
##
##   godot --path . tools/check_viewmodel.tscn -- --out=/tmp/vm
##
## Escribe idle / ads / fire / reload / reload_empty / inspect.

const POSE := {
	"idle": [0.0, 0.0, 0.0, 0.0],
	"ads": [1.0, 0.0, 0.0, 0.0],
	"fire": [0.0, 0.0, 0.0, 0.0],
	"reload": [0.0, 0.0, 1.0, 0.55],
	"reload_empty": [0.0, 0.0, 1.0, 0.15],
	"inspect": [0.0, 0.0, 0.55, 0.0],
}


## Caja envolvente de todo lo visible bajo un nodo.
func _visible_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			var world_box: AABB = (n as Node3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			box = world_box if first else box.merge(world_box)
			first = false
		for c in n.get_children():
			stack.append(c)
	return box


func _ready() -> void:
	var out_dir := "/tmp/vm"
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=")
		if kv.size() == 2 and kv[0] == "--out":
			out_dir = kv[1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var vp := SubViewport.new()
	vp.size = Vector2i(900, 700)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)

	var world_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.24, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 1.0)
	env.ambient_light_energy = 0.7
	world_node.environment = env
	vp.add_child(world_node)

	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.02
	cam.far = 20.0
	cam.current = true
	vp.add_child(cam)

	var vm: Node3D = GlockViewmodel.new()
	vp.add_child(vm)
	# La camara tiene que existir antes de montar: el ADS se resuelve al montar.
	vm.setup(cam)
	vm.mount()

	var weapon = vm.get("weapon")
	print("MONTAJE arma=", "si" if weapon != null else "NO")
	if weapon != null:
		print("  piezas: Frame=", weapon.frame != null, " Slide=", weapon.slide != null,
			" Magazine=", weapon.magazine != null, " Trigger=", weapon.trigger != null,
			" Barrel=", weapon.barrel != null)
		print("  puntos: boca=", weapon.muzzle != null, " puerto=", weapon.ejection_port != null,
			" mira_t=", weapon.sight_rear != null, " mira_d=", weapon.sight_front != null)
		print("  eje de salida del cargador ", weapon.magazine_out_axis().snapped(Vector3(0.01, 0.01, 0.01)))
	# Cuantas mallas quedan visibles y cuantos triangulos suman.
	var visible_meshes := []
	var tris := 0
	var stack: Array = [vm]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree():
			visible_meshes.append((n as MeshInstance3D).name)
			for si in range((n as MeshInstance3D).mesh.get_surface_count()):
				var arr: Array = (n as MeshInstance3D).mesh.surface_get_arrays(si)
				if arr.size() > 0 and arr[Mesh.ARRAY_INDEX] != null:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		for c in n.get_children():
			stack.append(c)
	print("  mallas visibles=", visible_meshes)
	print("  TRIANGULOS visibles=", tris)

	# Poses: la camara se coloca delante del viewmodel en el espacio de Glock.
	for pose_name in POSE:
		var pose: Array = POSE[pose_name]
		vm.set_pose_inputs(pose[0], 0.0, 0.0, Vector2.ZERO, Vector2.ZERO, pose[2])
		vm.set_magazine_visible(true)
		vm.set_magazine_offset(pose[3])
		for i in range(30):
			vm.update(1.0 / 60.0)
			await get_tree().process_frame
		# Encuadre automatico: se mira TODA la caja visible, no un punto fijo.
		var box := _visible_aabb(vm)
		var center := box.get_center()
		var radius := maxf(box.size.length() * 0.5, 0.15)
		print("  %s: largo visible mm %.1f" % [pose_name, maxf(box.size.x, maxf(box.size.y, box.size.z)) * 1000.0])
		cam.global_position = center + Vector3(radius * 1.1, radius * 0.35, radius * 1.6)
		cam.look_at(center, Vector3.UP)
		for i in range(6):
			await get_tree().process_frame
		vp.get_texture().get_image().save_png("%s/%s.png" % [out_dir, pose_name])
		print("  guardado ", pose_name)
	get_tree().quit()
