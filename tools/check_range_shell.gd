extends Node

## Invariante del asset de arquitectura: el GLB tiene pocas mallas, materiales
## PBR embebidos y ningun objeto de estaciones balisticas. Las colisiones y la
## sala acustica viven fuera del GLB, en Godot y en `default_bus_layout.tres`.

const SHELL_SCENE := preload("res://scenes/RangeShell.tscn")


func _ready() -> void:
	var shell := SHELL_SCENE.instantiate()
	add_child(shell)
	await get_tree().process_frame
	var visual := shell.get_node("Visual")
	var meshes := _mesh_nodes(visual)
	var failures := 0
	var materials := {}
	var bounds := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.mesh.surface_get_material(surface)
			if material != null:
				materials[material.resource_path if material.resource_path != "" else material.resource_name] = true
		var mesh_bounds: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		bounds = mesh_bounds if first else bounds.merge(mesh_bounds)
		first = false

	print("RangeShell mallas=", meshes.size(), " materiales=", materials.size(),
		" bounds=", bounds.size.snapped(Vector3(0.1, 0.1, 0.1)))
	if meshes.size() < 3 or meshes.size() > 8:
		failures += 1
		print("FALLO: RangeShell debe mantenerse en pocas mallas")
	if materials.size() < 3 or materials.size() > 8:
		failures += 1
		print("FALLO: RangeShell tiene una tabla de materiales fuera de alcance")
	if bounds.size.x < 23.0 or bounds.size.x > 25.0 \
			or bounds.size.y < 4.3 or bounds.size.y > 4.8 \
			or bounds.size.z < 70.0 or bounds.size.z > 74.0:
		failures += 1
		print("FALLO: dimensiones del rango fuera del instrumento 24 x 4,6 x 72 m")
	if _contains_rigidbody(visual) or _contains_name(visual, ["Can", "Crate", "Target", "Drywall"]):
		failures += 1
		print("FALLO: RangeShell contiene geometria funcional de estaciones")

	var expected_colliders := ["Floor", "Ceiling", "LeftWall", "RightWall", "FrontWall", "BackWall", "BulletTrap"]
	for node_name in expected_colliders:
		var body := shell.get_node_or_null(node_name)
		if body == null or not body is StaticBody3D or not body.has_meta("surface"):
			failures += 1
			print("FALLO: falta colision declarada de shell: ", node_name)

	if failures == 0:
		print("OK: RangeShell canonico y estaciones fuera del asset")
	get_tree().quit(1 if failures > 0 else 0)


func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			result.append(node as MeshInstance3D)
		for child in node.get_children():
			stack.append(child)
	return result


func _contains_rigidbody(root: Node) -> bool:
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is RigidBody3D:
			return true
		for child in node.get_children():
			stack.append(child)
	return false


func _contains_name(root: Node, names: Array[String]) -> bool:
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for name in names:
			if node.name.to_lower().contains(name.to_lower()):
				return true
		for child in node.get_children():
			stack.append(child)
	return false
