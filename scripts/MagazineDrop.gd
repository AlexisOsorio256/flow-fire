class_name MagazineDrop
extends RigidBody3D

## EL CARGADOR VACIO QUE SE VA: cuerpo fisico real con la malla del arma.
##
## Antes la recarga escondia el nodo del cargador a 7 cm del brocal y ahi se
## acababa: el cargador se desvanecia en el aire. Ahora el cargador sale del
## arma como una pieza suelta (`spawn`), sigue cayendo por el mundo con su
## malla, y el golpe contra el suelo lo dispara SU PROPIO contacto, no un
## cronometro: el sonido cae cuando el cargador toca, no cuando toca tocar.
##
## La malla es un duplicado del nodo `Magazine` de `GlockWeapon`: no hay una
## segunda malla de cargador en el proyecto ni una copia de sus materiales.
##
## El nodo del arma y este cuerpo son el MISMO cargador en dos tramos: el nodo
## lo saca del brocal pegado al arma y, en cuanto esta libre, Glock lo suelta
## aqui. Solo uno de los dos dibuja cada tramo.

## Cargador vacio ~71 g; cada cartucho 9x19 ~12 g. Lo eyectado se pierde.
const MASS_EMPTY := 0.071
const MASS_PER_ROUND := 0.012
## Rebote y roce contra hormigon: cae de canto, bota poco y se arrastra.
const BOUNCE := 0.28
const FRICTION := 0.55
## Velocidad minima de choque para que se oiga (por debajo solo rueda).
const PING_SPEED := 0.45
## Se queda en el suelo un rato y se limpia solo: el rango no se llena de
## cargadores por mucho que se recargue.
const LIFE := 20.0

var life := 0.0
var last_ping := -1.0


## Suelta el cargador de `source` en la escena, con la velocidad con la que sale
## del arma. `spin` es su giro (rad/s): un cargador recien soltado voltea.
static func spawn(scene: Node, source: Node3D, velocity: Vector3, spin: Vector3, rounds := 0) -> MagazineDrop:
	var mag := MagazineDrop.new()
	mag.name = "MagazineDrop"
	mag.mass = MASS_EMPTY + maxf(0.0, float(rounds)) * MASS_PER_ROUND
	mag.collision_layer = 2
	mag.collision_mask = 1
	mag.continuous_cd = true

	# El duplicado pierde la escala que el arma le daba por herencia, asi que se
	# le devuelve en su propio transform: el cargador tiene que medir lo mismo
	# suelto que dentro del arma.
	var scale: Vector3 = source.global_transform.basis.get_scale()
	var visual: Node3D = source.duplicate() as Node3D
	visual.transform = Transform3D(Basis.IDENTITY.scaled(scale), Vector3.ZERO)
	visual.visible = true
	_set_world_layers(visual)
	mag.add_child(visual)

	var box: AABB = _visual_aabb(visual)
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = box.get_center()
	mag.add_child(collider)

	var material := PhysicsMaterial.new()
	material.bounce = BOUNCE
	material.friction = FRICTION
	mag.physics_material_override = material
	mag.linear_damp = 0.08
	mag.angular_damp = 0.30

	scene.add_child(mag)
	mag.global_transform = source.global_transform
	mag.linear_velocity = velocity
	mag.angular_velocity = spin
	return mag


## El cargador deja de ser viewmodel: ahora lo alumbran y lo recortan las luces
## y la camara del mundo.
static func _set_world_layers(root: Node) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is VisualInstance3D:
			(n as VisualInstance3D).layers = 1
		for c in n.get_children():
			stack.append(c)


static func _visual_aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var world_box: AABB = (n as Node3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			box = world_box if first else box.merge(world_box)
			first = false
		for c in n.get_children():
			stack.append(c)
	return box


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	life += delta
	if life > LIFE:
		queue_free()


func _on_body_entered(_body: Node) -> void:
	if life < 0.04:
		return
	var speed := linear_velocity.length()
	if speed < PING_SPEED:
		return
	# Cada contacto real suena: la muestra debe ser UN golpe, no cinco rebotes
	# horneados. Nivel y pitch derivan de la velocidad, como Shell.
	if life - last_ping < 0.12:
		return
	last_ping = life
	var db := clampf(-6.0 + speed * 1.2, -6.0, 2.0)
	GameAudio.play_3d("mag_drop", global_position, db, randf_range(0.92, 1.08) + speed * 0.01)
