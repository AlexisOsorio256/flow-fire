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
var table_mat: StandardMaterial3D
var mag_prop_mat: StandardMaterial3D
## Municion de LABORATORIO: 4 cargadores de 15 sobre la mesa y se regeneran.
## El arma no tiene `reserve`; la recarga consume uno de aqui al acercarse.
##
## La mesa es un BANCO DE PRUEBAS, no un inventario: el objetivo es poder probar
## la Glock indefinidamente. Por eso los cargadores vuelven solos tras
## TABLE_REGEN_S sin haber usado la mesa. No hay economia, ni compra, ni
## contador global: un reloj y cuatro posiciones.
const TABLE_MAGS_MAX := 4
const TABLE_MAG_ROUNDS := 15
const TABLE_POS := Vector3(1.8, 0.0, -1.4)
const TABLE_REACH := 1.6
## Segundos sin tocar la mesa hasta que vuelve a estar llena. Uno a uno, no de
## golpe: se ve reaparecer el que falta, que es mas honesto que un salto.
const TABLE_REGEN_S := 6.0
var table_mags := TABLE_MAGS_MAX
var _mag_props: Array[Node3D] = []
var _regen_clock := 0.0


func build() -> void:
    _materials()
    _build_props()
    _build_targets()
    _build_mag_table()


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

    table_mat = StandardMaterial3D.new()
    table_mat.albedo_color = Color(0.32, 0.30, 0.27)
    table_mat.roughness = 0.8

    mag_prop_mat = StandardMaterial3D.new()
    mag_prop_mat.albedo_color = Color(0.12, 0.12, 0.14)
    mag_prop_mat.metallic = 0.6
    mag_prop_mat.roughness = 0.45

func _build_props() -> void:
    # LAS PLANCHAS DE ACERO YA NO ESTAN, y es una decision del dueño del repo,
    # no una perdida: eran cinco mamparas atravesadas en los carriles que
    # bloqueaban el paso y la linea de tiro ("no quiero que esten los fierros,
    # debe estar sin eso [para] moverme por donde yo quiero en todo el mapa").
    # El rango es un instrumento de medida: se camina por el y se dispara a lo
    # que hay, sin escondites de por medio. `_make_barrier` se va con ellas.

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

    # ---------------------------------------------------- QUE HAYA QUE DISPARAR
    # Peticion del dueño: "no le puedo disparar a nada porque no hay nada".
    # Tenia razon y era literal: lo mas cercano estaba a 8 m y TODA la mitad de
    # atras del rango (z > 0, 66 m de pasillo) estaba vacia, asi que caminar
    # hacia atras era caminar por una nave en obra. Esto no son "estaciones de
    # medida" -- esas siguen siendo las de `_build_targets` -- es material para
    # tener algo delante a cualquier distancia y en cualquier direccion.
    # Todo reutiliza los constructores que ya existen, con su material real
    # (lata = thin_shell de aluminio, caja = pino hueco, bidon = acero).
    # Fila de latas a 2 m del puesto: lo primero que se ve al levantar el arma.
    for i in range(5):
        _make_can(Vector3(-3.2 + i * 1.6, 0.061, -5.6))
    # Y blancos GRANDES a 6 y 8 m, que es lo que se echa en falta de verdad:
    # una lata a 6 m son 14 px y no se ve. Tres de acero (chispa y suena) y dos
    # de papel (agujero limpio) delante de las narices, sin tener que ir a
    # buscarlos a 18 m.
    for i in range(3):
        _make_steel_target(-2.0 + i * 2.0, -6.0)
    for i in range(2):
        _make_paper_target(-1.0 + i * 2.0, -8.0)
    # Otra fila a 7 m, esta vez sobre una tabla baja: obliga a apuntar.
    _make_plank_wall(5.6, -7.2, deg_to_rad(0.0))
    for i in range(3):
        _make_can(Vector3(5.0 + i * 0.6, 0.061, -7.4))
    # NADA DETRAS DE LA LINEA DE TIRO. El dueño lo dijo sin rodeos: "no tiene
    # sentido que se pongan esas cosas asi, es hacia atras". Tenia razon: el
    # rango se dispara hacia -Z y poner material a la espalda del tirador no es
    # un rango, es almacen. Todo lo que hay para disparar esta DELANTE.

    # ------------------------------------------------- EL PASILLO, LLENO
    # Peticion del dueño: "todo lo bueno para tirarle -- madera, latas, botes,
    # paredes para traspasar -- va en el pasillo grande y bien iluminado, para
    # divertirme". Va TODO delante de la linea de tiro, de 3 m a 55 m, para que
    # se pueda caminar hacia el fondo disparando sin quedarse sin nada. La otra
    # mitad del rango se queda vacia (lo pidio asi) pero con luz.
    # Nada de geometria nueva: se reutilizan los constructores que ya existen.
    _make_plank_wall(4.6, -10.5, deg_to_rad(-9.0))
    _make_plank_wall(-5.2, -17.0, deg_to_rad(12.0))
    _make_plank_wall(5.4, -30.0, deg_to_rad(-7.0))
    _make_plank_wall(-5.0, -42.0, deg_to_rad(6.0))
    _make_drywall_panel(Vector3(-8.6, 0.0, -14.0), Vector2(2.6, 2.4), deg_to_rad(0.0))
    _make_drywall_panel(Vector3(8.6, 0.0, -18.0), Vector2(2.6, 2.4), deg_to_rad(0.0))
    _make_drywall_panel(Vector3(-8.0, 0.0, -33.0), Vector2(2.6, 2.4), deg_to_rad(0.0))
    _make_drywall_panel(Vector3(8.0, 0.0, -44.0), Vector2(2.6, 2.4), deg_to_rad(0.0))
    # Bidones de acero repartidos por todo el pasillo: son los que suenan.
    for z in [-8.6, -16.0, -21.0, -29.0, -38.0, -47.0]:
        _make_drum(-6.6 if int(z) % 2 == 0 else 6.6, z)
    # Torres de cajas de pino (huecas, se atraviesan): a varias distancias.
    for z in [-7.0, -19.0, -26.0, -34.0, -45.0]:
        for level in range(2):
            _make_crate(Vector3(3.4, 0.35 * level, z), 0.35)
    # Latas: el caso de prueba de `thin_shell`. Sueltas por el suelo y de pie
    # sobre los bidones, de cerca a lejos.
    for i in range(6):
        _make_can(Vector3(-4.4 + i * 0.55, 0.061, -3.7))
    for z in [-9.0, -13.0, -20.0, -23.0, -31.0, -36.0, -40.0, -48.0, -53.0]:
        _make_can(Vector3(-1.2 + float(z) * 0.05, 0.061, z))

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


func _make_plank_wall(x: float, z: float, rot_y: float) -> void:
    var root := Node3D.new()
    root.name = "PlankWall"
    root.position = Vector3(x, 0, z)
    root.rotation.y = rot_y
    add_child(root)
    for i in range(5):
        var plank := _static_box(root, "Plank", Vector3(0.22, 1.9, 0.045), Vector3((i - 2) * 0.25, 0.95, 0), wood_mat)
        plank.set_meta("surface", "pine")
        plank.set_meta("penetrable", true)
    for rail_y in [0.5, 1.5]:
        var rail := _static_box(root, "PlankRail", Vector3(1.3, 0.09, 0.03), Vector3(0, rail_y, -0.05), wood_mat)
        rail.set_meta("surface", "pine")
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
    body.set_meta("surface", "steel")
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
        post.set_meta("surface", "steel")
    var base := _static_box(frame, "Base", Vector3(1.1, 0.06, 0.5), Vector3(0, 0.03, -0.12), stand_mat)
    base.set_meta("surface", "steel")

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
    post.set_meta("surface", "steel")
    var base := _static_box(frame, "SteelBase", Vector3(0.7, 0.06, 0.5), Vector3(0, 0.03, -0.10), stand_mat)
    base.set_meta("surface", "steel")

    var target := Target.new()
    target.kind = "steel"
    target.name = "SteelTarget"
    add_child(target)
    target.global_position = Vector3(x, 1.35, z)

    _make_joint(frame, target, Vector3(x, 1.66, z))


## Mesa de cargadores: la fuente fisica de municion. Sin inventario ni manager:
## 4 cuerpos sobre la mesa, cada uno 15. Acercarse + R consume uno.
func _process(delta: float) -> void:
    # Regeneracion de la mesa: un cargador cada TABLE_REGEN_S, solo si falta
    # alguno. Determinista y visible: reaparece donde estaba.
    if table_mags < TABLE_MAGS_MAX:
        _regen_clock += delta
        if _regen_clock >= TABLE_REGEN_S:
            _regen_clock = 0.0
            table_mags += 1
            var prop: Node3D = _mag_props[table_mags - 1]
            if is_instance_valid(prop):
                prop.visible = true
    else:
        _regen_clock = 0.0


func _build_mag_table() -> void:
    var table := StaticBody3D.new()
    table.name = "MagTable"
    table.position = TABLE_POS
    add_child(table)
    table.set_meta("surface", "pine")
    var top := MeshInstance3D.new()
    var top_mesh := BoxMesh.new()
    top_mesh.size = Vector3(0.7, 0.05, 0.5)
    top_mesh.material = table_mat
    top.mesh = top_mesh
    top.position = Vector3(0, 0.75, 0)
    table.add_child(top)
    var top_col := CollisionShape3D.new()
    var top_shape := BoxShape3D.new()
    top_shape.size = Vector3(0.7, 0.05, 0.5)
    top_col.shape = top_shape
    top_col.position = Vector3(0, 0.75, 0)
    table.add_child(top_col)
    for leg_x in [-0.3, 0.3]:
        for leg_z in [-0.2, 0.2]:
            var leg := MeshInstance3D.new()
            var leg_mesh := BoxMesh.new()
            leg_mesh.size = Vector3(0.05, 0.75, 0.05)
            leg_mesh.material = table_mat
            leg.mesh = leg_mesh
            leg.position = Vector3(leg_x, 0.375, leg_z)
            table.add_child(leg)
    _mag_props.clear()
    for i in range(TABLE_MAGS_MAX):
        var prop := Node3D.new()
        prop.name = "TableMag%d" % (i + 1)
        # Silueta de cargador de G19: cuerpo, base y labios. Una caja de 28 mm
        # no se lee como cargador a un metro de distancia; estas tres piezas si,
        # y siguen siendo 3 mallas minusculas.
        var body := _mag_piece(Vector3(0.026, 0.098, 0.037), Vector3(0.0, 0.0, 0.0))
        prop.add_child(body)
        var base := _mag_piece(Vector3(0.030, 0.012, 0.044), Vector3(0.0, -0.053, 0.002))
        prop.add_child(base)
        var lips := _mag_piece(Vector3(0.022, 0.012, 0.032), Vector3(0.0, 0.053, -0.004))
        prop.add_child(lips)
        prop.position = Vector3(-0.21 + i * 0.14, 0.845, 0.0)
        prop.rotation.z = deg_to_rad(-8.0)
        table.add_child(prop)
        _mag_props.append(prop)


## Una pieza del cargador de la mesa, con el material unico de la mesa.
func _mag_piece(size: Vector3, offset: Vector3) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    bm.material = mag_prop_mat
    mi.mesh = bm
    mi.position = offset
    return mi


## Se PUEDE tomar un cargador? No consume nada: es la pregunta que hay que
## hacer ANTES de tocar el inventario. Antes solo existia `try_take_mag`, que
## restaba primero y devolvia las balas despues, asi que `start_reload` podia
## fallar (recarga en curso, cargador lleno) con el cargador YA gastado: se
## perdia municion sin recargar. Ahora se valida y luego se consume.
func can_take_mag(player_pos: Vector3) -> bool:
    return table_mags > 0 and player_pos.distance_to(TABLE_POS) <= TABLE_REACH


## Consume un cargador de la mesa y devuelve sus cartuchos. SOLO se llama
## despues de `can_take_mag` y de que el arma haya aceptado la recarga.
func consume_mag() -> int:
    if table_mags <= 0:
        return 0
    table_mags -= 1
    _regen_clock = 0.0
    if _mag_props.size() > table_mags:
        var prop: Node3D = _mag_props[table_mags]
        if is_instance_valid(prop):
            prop.visible = false
    return TABLE_MAG_ROUNDS


func table_near(player_pos: Vector3) -> bool:
    return player_pos.distance_to(TABLE_POS) <= TABLE_REACH


func _make_joint(frame: StaticBody3D, target: RigidBody3D, pivot: Vector3) -> void:
    var joint := PinJoint3D.new()
    frame.add_child(joint)
    joint.node_a = frame.get_path()
    joint.node_b = target.get_path()
    joint.global_position = pivot
