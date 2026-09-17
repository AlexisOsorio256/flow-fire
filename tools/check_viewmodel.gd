extends Node
## Renderiza el viewmodel a PNG en varias poses, sin depender de que la ventana
## del juego se vea. Es una sonda de lectura: deja mirar que hay montado.

const POSE := {
	"idle": [0.0, 0.0, 0.0],
	"ads": [1.0, 0.0, 0.0],
	"fire": [0.0, 0.0, 0.0],
	"reload": [0.0, 0.0, 1.0],
	"inspect": [0.0, 0.0, 0.0],
}


## Caja envolvente de todo lo visible bajo un nodo.
func _caja_visible(raiz: Node) -> AABB:
	var caja := AABB()
	var primero := true
	var pila: Array = [raiz]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			var mundo: AABB = (n as Node3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			caja = mundo if primero else caja.merge(mundo)
			primero = false
		for c in n.get_children():
			pila.append(c)
	return caja


func _ready() -> void:
	var salida := "/tmp/vm"
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).split("=")
		if kv.size() == 2 and kv[0] == "--out":
			salida = kv[1]
	DirAccess.make_dir_recursive_absolute(salida)

	var vp := SubViewport.new()
	vp.size = Vector2i(900, 700)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)

	var entorno := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.24, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.85, 1.0)
	env.ambient_light_energy = 0.7
	entorno.environment = env
	vp.add_child(entorno)

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

	var arma = vm.get("weapon")
	print("MONTAJE arma=", "si" if arma != null else "NO", " brazos=", vm.arms_ok)
	if arma != null:
		print("  piezas: Frame=", arma.frame != null, " Slide=", arma.slide != null,
			" Magazine=", arma.magazine != null, " Trigger=", arma.trigger != null,
			" Barrel=", arma.barrel != null)
		print("  puntos: boca=", arma.muzzle != null, " puerto=", arma.ejection_port != null,
			" mira_t=", arma.sight_rear != null, " mira_d=", arma.sight_front != null)
	print("  malla brazos=", vm.arms_mesh_visible.name if vm.arms_mesh_visible else "NINGUNA",
		" manga=", vm.arms_sleeve_visible.name if vm.arms_sleeve_visible else "NINGUNA")
	if vm.arms_skeleton != null:
		print("  huesos del rig de brazos=", vm.arms_skeleton.get_bone_count())
	# Cuantas mallas quedan visibles y cuantos triangulos suman.
	var visibles := []
	var tris := 0
	var pila: Array = [vm]
	while not pila.is_empty():
		var n = pila.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree():
			visibles.append((n as MeshInstance3D).name)
			for si in range((n as MeshInstance3D).mesh.get_surface_count()):
				var arr: Array = (n as MeshInstance3D).mesh.surface_get_arrays(si)
				if arr.size() > 0 and arr[Mesh.ARRAY_INDEX] != null:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		for c in n.get_children():
			pila.append(c)
	print("  mallas visibles=", visibles)
	print("  TRIANGULOS visibles=", tris)

	# Poses: la camara se coloca delante del viewmodel en el espacio de Glock.
	for nombre in POSE:
		var modo: Array = POSE[nombre]
		vm.set_pose_inputs(modo[0], 0.0, 0.0, Vector2.ZERO, Vector2.ZERO, modo[2])
		if nombre == "fire":
			vm.play_fire()
		elif nombre == "reload":
			vm.play_reload(false)
		elif nombre == "inspect":
			vm.play_anim("Inspect")
		else:
			vm.play_anim("Idle", true)
		for i in range(30):
			vm.update(1.0 / 60.0)
			await get_tree().process_frame
		# Encuadre automatico: se mira TODA la caja visible, no un punto fijo.
		var caja := _caja_visible(vm)
		var centro := caja.get_center()
		var radio := maxf(caja.size.length() * 0.5, 0.15)
		cam.global_position = centro + Vector3(radio * 1.1, radio * 0.35, radio * 1.6)
		cam.look_at(centro, Vector3.UP)
		for i in range(6):
			await get_tree().process_frame
		vp.get_texture().get_image().save_png("%s/%s.png" % [salida, nombre])
		print("  guardado ", nombre)
	get_tree().quit()
