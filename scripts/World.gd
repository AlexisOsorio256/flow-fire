extends Node3D

const WOOD_ALBEDO: Texture2D = preload("res://assets/textures/real/wood_oak_wood_planks_diff.jpg")
const WOOD_NORMAL: Texture2D = preload("res://assets/textures/real/wood_oak_wood_planks_nor_gl.jpg")
const WOOD_ROUGHNESS: Texture2D = preload("res://assets/textures/real/wood_oak_wood_planks_rough.jpg")
const METAL_ALBEDO: Texture2D = preload("res://assets/textures/real/metal_metal_plate_diff.jpg")
const METAL_NORMAL: Texture2D = preload("res://assets/textures/real/metal_metal_plate_nor_gl.jpg")
const METAL_ROUGHNESS: Texture2D = preload("res://assets/textures/real/metal_metal_plate_rough.jpg")

var wood_mat: StandardMaterial3D
var drum_mat: StandardMaterial3D
var stand_mat: StandardMaterial3D
var drywall_mat: StandardMaterial3D
var can_mat: StandardMaterial3D


func build() -> void:
    _materials()
    _build_props()
    _build_targets()


func _materials() -> void:
    wood_mat = StandardMaterial3D.new()
    wood_mat.albedo_texture = WOOD_ALBEDO
    wood_mat.roughness_texture = WOOD_ROUGHNESS
    wood_mat.normal_enabled = true
    wood_mat.normal_texture = WOOD_NORMAL
    wood_mat.normal_scale = 1.0
    wood_mat.uv1_scale = Vector3(1.5, 1, 1.5)
    wood_mat.roughness = 0.8

    # Bidon de acero PINTADO (negro industrial), no chapa desnuda: un metal
    # 0,9 en un interior oscuro sale negro puro y los agujeros no se leen.
    # Dielectrico oscuro con la misma foto de acero debajo: difuso real.
    drum_mat = StandardMaterial3D.new()
    drum_mat.albedo_texture = METAL_ALBEDO
    drum_mat.albedo_color = Color(0.16, 0.17, 0.19)
    drum_mat.roughness_texture = METAL_ROUGHNESS
    drum_mat.normal_enabled = true
    drum_mat.normal_texture = METAL_NORMAL
    drum_mat.normal_scale = 0.8
    drum_mat.metallic = 0.0
    drum_mat.roughness = 0.55
    drum_mat.uv1_scale = Vector3(2, 2, 2)

    stand_mat = StandardMaterial3D.new()
    stand_mat.albedo_color = Color(0.18, 0.19, 0.21)
    stand_mat.metallic = 0.75
    stand_mat.roughness = 0.42

    # Lata de aluminio: metal claro, casi sin espesor. La balistica no la trata
    # como un cilindro macizo (ver `_make_can`).
    can_mat = StandardMaterial3D.new()
    can_mat.albedo_color = Color(0.78, 0.80, 0.84)
    can_mat.metallic = 0.85
    can_mat.roughness = 0.32

    drywall_mat = StandardMaterial3D.new()
    drywall_mat.albedo_color = Color(0.80, 0.78, 0.73)
    drywall_mat.roughness = 0.92
    drywall_mat.uv1_scale = Vector3(2, 2, 2)

func _build_props() -> void:
    _make_barrier(-5.8, -8.0, deg_to_rad(-8.0))
    _make_barrier(5.6, -14.5, deg_to_rad(10.0))
    _make_barrier(-5.4, -22.0, deg_to_rad(-6.0))
    # Coberturas deliberadas: la de x=-2 cubre el blanco de papel de x=-2
    # (se tira A TRAVES de la tabla: 55 mm de pino los pasa sobrados) y la
    # de x=3 cubre el acero (ahi no hay paso: chispa y nada mas).
    _make_barrier(-2.0, -16.5, deg_to_rad(20.0))
    _make_barrier(3.0, -24.5, deg_to_rad(-18.0))

    _make_plank_wall(-2.5, -12.0, deg_to_rad(15.0))
    # Torre de 4: el tiro de pie (~1.37 m a 2.5 m) da al cajon alto. Una 9 mm
    # que lo atraviesa le deja ~0,2 N.s a 4,2 kg: tiembla, no vuelca (medido:
    # 0,04 m/s de pico). El vuelco seria inventar momento; la caja responde
    # con agujeros que viajan con ella. El sencillo queda para tiro picado.
    _make_crate(Vector3(4.8, 0.0, -9.5), 0.35)
    _make_crate(Vector3(4.8, 0.35, -9.5), 0.35)
    _make_crate(Vector3(4.8, 0.70, -9.5), 0.35)
    _make_crate(Vector3(4.8, 1.05, -9.5), 0.35)
    _make_crate(Vector3(-7.2, 0.0, -20.5), 0.35)

    _make_drum(6.6, -11.0)
    _make_drum(-6.8, -25.0)
    _make_drum(7.2, -27.0)

    # Pladur/yeso penetrable: entrada, salida y paso de bala visibles.
    _make_drywall_panel(Vector3(-8.6, 0.0, -14.0), Vector2(2.6, 2.4), deg_to_rad(0.0))
    _make_drywall_panel(Vector3(8.6, 0.0, -18.0), Vector2(2.6, 2.4), deg_to_rad(0.0))

    # Latas: cascara fina penetrable sobre el bidon de x=6.6 y en el suelo. Son
    # el caso de prueba de `thin_shell`: la bala las atraviesa perdiendo casi
    # nada y Jolt las tira y las hace rodar.
    _make_can(Vector3(6.52, 0.98, -10.92))
    _make_can(Vector3(6.68, 0.98, -11.04))
    _make_can(Vector3(6.60, 0.98, -11.16))
    _make_can(Vector3(-1.60, 0.061, -13.60))
    _make_can(Vector3(-1.40, 0.061, -13.72))


func _build_targets() -> void:
    # Estaciones de medicion: 18 m papel, 27 m acero/angulos, 35 m agrupacion,
    # 50 m caida/zero. Cada cosa responde una pregunta concreta.
    for i in range(5):
        _make_paper_target(-4.0 + i * 2.0, -18.0)
    for i in range(3):
        _make_steel_target(-3.0 + i * 3.0, -27.0)
    for i in range(3):
        _make_paper_target(-2.0 + i * 2.0, -35.0)
    _make_steel_target(0.0, -50.0)


func _static_box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = node_name
    body.position = pos
    parent.add_child(body)

    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    box.material = mat
    mesh.mesh = box
    body.add_child(mesh)

    var shape := CollisionShape3D.new()
    var box_shape := BoxShape3D.new()
    box_shape.size = size
    shape.shape = box_shape
    body.add_child(shape)
    return body


func _make_barrier(x: float, z: float, rot_y: float) -> void:
    var root := Node3D.new()
    root.position = Vector3(x, 0, z)
    root.rotation.y = rot_y
    add_child(root)

    var board := _static_box(root, "BarrierBoard", Vector3(2.3, 0.72, 0.055), Vector3(0, 1.08, 0), wood_mat)
    board.set_meta("surface", "wood")
    board.set_meta("penetrable", true)

    for leg_x in [-1.0, 1.0]:
        var leg := _static_box(root, "BarrierLeg", Vector3(0.08, 1.05, 0.08), Vector3(leg_x, 0.52, 0), wood_mat)
        leg.set_meta("surface", "wood")


## Muro de tablones con rendijas (45 mm de pino): lo atraviesa una 9 mm
## perdiendo ~15% de velocidad por tablon; por las rendijas pasa intacta.
func _make_plank_wall(x: float, z: float, rot_y: float) -> void:
    var root := Node3D.new()
    root.name = "PlankWall"
    root.position = Vector3(x, 0, z)
    root.rotation.y = rot_y
    add_child(root)
    for i in range(5):
        var plank := _static_box(root, "Plank", Vector3(0.22, 1.9, 0.045), Vector3((i - 2) * 0.25, 0.95, 0), wood_mat)
        plank.set_meta("surface", "wood")
        plank.set_meta("penetrable", true)
    for rail_y in [0.5, 1.5]:
        var rail := _static_box(root, "PlankRail", Vector3(1.3, 0.09, 0.03), Vector3(0, rail_y, -0.05), wood_mat)
        rail.set_meta("surface", "wood")
        rail.set_meta("penetrable", true)


## Caja de madera (35 cm): la 9 mm la pasa saliendo lenta (~110 m/s, al limite
## del modelo); dos cajas pegadas ya la detienen. Entrenamiento de libro.
## Son cuerpos rigidos (ver Crate.gd): el impacto las empuja y voltea, y los
## agujeros viajan con ellas.
## Caja HUECA honesta: 6 paneles de pino de 12 mm, no bloque macizo.
## La bala atraviesa dos paredes (24 mm), no 350 mm de madera.
func _make_crate(base: Vector3, size: float) -> void:
    var box := Crate.new()
    box.name = "WoodCrate"
    box.mass = 4.2
    box.position = base + Vector3(0, size * 0.5, 0)
    add_child(box)
    var t := 0.012
    var panels := [
        [Vector3(size, t, size), Vector3(0, -size * 0.5 + t * 0.5, 0)],
        [Vector3(size, t, size), Vector3(0, size * 0.5 - t * 0.5, 0)],
        [Vector3(size, size, t), Vector3(0, 0, -size * 0.5 + t * 0.5)],
        [Vector3(size, size, t), Vector3(0, 0, size * 0.5 - t * 0.5)],
        [Vector3(t, size, size), Vector3(-size * 0.5 + t * 0.5, 0, 0)],
        [Vector3(t, size, size), Vector3(size * 0.5 - t * 0.5, 0, 0)],
    ]
    for panel in panels:
        var psize: Vector3 = panel[0] as Vector3
        var ppos: Vector3 = panel[1] as Vector3
        var mi := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = psize
        bm.material = wood_mat
        mi.mesh = bm
        mi.position = ppos
        box.add_child(mi)
        var cs := CollisionShape3D.new()
        var bs := BoxShape3D.new()
        bs.size = psize
        cs.shape = bs
        cs.position = ppos
        box.add_child(cs)


func _make_drywall_panel(base: Vector3, panel_size: Vector2, rot_y: float) -> void:
    var root := Node3D.new()
    root.name = "DrywallPanel"
    root.position = base
    root.rotation.y = rot_y
    add_child(root)
    var body := _static_box(root, "DrywallSheet", Vector3(panel_size.x, panel_size.y, 0.0127), Vector3(0.0, panel_size.y * 0.5, 0.0), drywall_mat)
    body.set_meta("surface", "gypsum")
    body.set_meta("penetrable", true)
    # Hoja honesta de 1/2" (12,7 mm): la tabla balistica se resuelve en
    # Ballistics.MATERIALS y este cuerpo solo declara material + geometria.


func _make_drum(x: float, z: float) -> void:
    var body := StaticBody3D.new()
    body.name = "SteelDrum"
    body.position = Vector3(x, 0.46, z)
    add_child(body)

    var mesh_instance := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.height = 0.92
    mesh.top_radius = 0.29
    mesh.bottom_radius = 0.29
    mesh.radial_segments = 24
    mesh.material = drum_mat
    mesh_instance.mesh = mesh
    body.add_child(mesh_instance)

    var shape := CollisionShape3D.new()
    var cyl := CylinderShape3D.new()
    cyl.height = 0.92
    cyl.radius = 0.29
    shape.shape = cyl
    body.add_child(shape)
    body.set_meta("surface", "metal")
    body.set_meta("penetrable", true)
    body.set_meta("thin_shell", true)
    body.set_meta("wall_thickness", 0.0012)


## Lata de aluminio vacia. Jolt la mueve (rueda, rebota, se voltea) con una
## CylinderShape3D, pero la balistica NO la trata como un cilindro macizo de
## aluminio: es una cascara de 0,12 mm, asi que declara `thin_shell` y la bala
## pierde energia en DOS paredes finas, no en 66 mm de metal. El aire de dentro
## no frena nada.
func _make_can(base: Vector3) -> void:
    var body := RigidBody3D.new()
    body.name = "Can"
    body.mass = 0.014
    body.collision_layer = 1
    body.collision_mask = 1
    body.continuous_cd = true
    body.linear_damp = 0.12
    body.angular_damp = 0.18
    body.position = base
    add_child(body)

    var mesh_instance := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.height = 0.122
    mesh.top_radius = 0.033
    mesh.bottom_radius = 0.033
    mesh.radial_segments = 20
    mesh.material = can_mat
    mesh_instance.mesh = mesh
    body.add_child(mesh_instance)

    var shape := CollisionShape3D.new()
    var cyl := CylinderShape3D.new()
    cyl.height = 0.122
    cyl.radius = 0.033
    shape.shape = cyl
    body.add_child(shape)

    var mat := PhysicsMaterial.new()
    mat.bounce = 0.28
    mat.friction = 0.5
    body.physics_material_override = mat

    body.set_meta("dynamic_decal", true)
    body.set_meta("surface", "aluminum")
    body.set_meta("penetrable", true)
    body.set_meta("thin_shell", true)
    body.set_meta("wall_thickness", 0.00012)
    # Aluminio: la tabla balistica lo mantiene separado del acero.


func _make_paper_target(x: float, z: float) -> void:
    var frame := StaticBody3D.new()
    frame.name = "PaperTargetFrame"
    frame.position = Vector3(x, 0, z)
    add_child(frame)

    for post_x in [-0.42, 0.42]:
        var post := _static_box(frame, "Post", Vector3(0.05, 1.78, 0.05), Vector3(post_x, 0.89, -0.12), stand_mat)
        post.set_meta("surface", "metal")
    var base := _static_box(frame, "Base", Vector3(1.1, 0.06, 0.5), Vector3(0, 0.03, -0.12), stand_mat)
    base.set_meta("surface", "metal")

    var target := Target.new()
    target.kind = "paper"
    target.name = "PaperTarget"
    add_child(target)
    target.global_position = Vector3(x, 1.35, z)

    _make_joint(frame, target, Vector3(x, 1.80, z))


func _make_steel_target(x: float, z: float) -> void:
    var frame := StaticBody3D.new()
    frame.name = "SteelTargetFrame"
    frame.position = Vector3(x, 0, z)
    add_child(frame)

    var post := _static_box(frame, "SteelPost", Vector3(0.07, 1.62, 0.07), Vector3(0, 0.81, -0.10), stand_mat)
    post.set_meta("surface", "metal")
    var base := _static_box(frame, "SteelBase", Vector3(0.7, 0.06, 0.5), Vector3(0, 0.03, -0.10), stand_mat)
    base.set_meta("surface", "metal")

    var target := Target.new()
    target.kind = "steel"
    target.name = "SteelTarget"
    add_child(target)
    target.global_position = Vector3(x, 1.35, z)

    _make_joint(frame, target, Vector3(x, 1.66, z))


func _make_joint(frame: StaticBody3D, target: RigidBody3D, pivot: Vector3) -> void:
    var joint := PinJoint3D.new()
    frame.add_child(joint)
    joint.node_a = frame.get_path()
    joint.node_b = target.get_path()
    joint.global_position = pivot
