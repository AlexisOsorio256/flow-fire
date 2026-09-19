extends Node
## Mide el Grip REAL de la pistola en el espacio del arma: posicion, ejes
## (arriba/adelante/lateral) y el recorrido de la empunadura. Con esto se
## coloca la mano contra la geometria, no a ojo.

func _ready() -> void:
	var w := GlockWeapon.new()
	add_child(w)
	if not w.build():
		push_error("no monto")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	w.force_update_transform()
	var g := w.grip
	print("GRIP pos(local en Weapon)=", g.position.snapped(Vector3.ONE * 0.0001))
	print("GRIP basis X(der)=", (g.global_transform.basis.x).normalized().snapped(Vector3.ONE*0.001))
	print("GRIP basis Y(arriba)=", (g.global_transform.basis.y).normalized().snapped(Vector3.ONE*0.001))
	print("GRIP basis Z=", (g.global_transform.basis.z).normalized().snapped(Vector3.ONE*0.001))
	var box := AABB()
	var first := true
	var stack: Array = [w.frame]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var lb: AABB = (n as MeshInstance3D).mesh.get_aabb()
			box = lb if first else box.merge(lb)
			first = false
		for c in n.get_children():
			stack.append(c)
	print("FRAME aabb pos=", box.position.snapped(Vector3.ONE*0.001), " size=", box.size.snapped(Vector3.ONE*0.001))
	print("MAGWELL pos=", w.magwell.position.snapped(Vector3.ONE*0.0001))
	print("MUZZLE pos=", w.muzzle.position.snapped(Vector3.ONE*0.0001))
	var total := AABB()
	var f2 := true
	var st2: Array = [w]
	while not st2.is_empty():
		var n = st2.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var lb: AABB = w.global_transform.affine_inverse() * mi.global_transform * mi.mesh.get_aabb()
			total = lb if f2 else total.merge(lb)
			f2 = false
		for c in n.get_children():
			st2.append(c)
	print("ARMA aabb pos=", total.position.snapped(Vector3.ONE*0.001), " size=", total.size.snapped(Vector3.ONE*0.001))
	get_tree().quit()
