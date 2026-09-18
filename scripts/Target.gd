extends RigidBody3D
class_name Target

## BLANCO REACTIVO, sin juego dentro: recibe la bala, la marca y la empuja.
##
## No hay vida, ni zonas, ni muerte, ni multiplicadores. Este proyecto es un
## laboratorio de la Glock: lo que se mide de un blanco es como lo golpea la
## bala (impulso, penetracion, marcas), no cuanto dano acumula.
##
## Dos materiales honestos:
##   paper  hoja penetrable, cuelga de un pin y se deja mecer
##   steel  placa no penetrable, devuelve chispa y retrocede poco

var kind := "paper"
var plate_height := 0.9
var plate_width := 0.66

var plate_mesh: MeshInstance3D
var base_material: StandardMaterial3D


func _ready() -> void:
    mass = 0.4 if kind == "paper" else 6.0
    collision_layer = 1
    collision_mask = 1
    continuous_cd = true
    set_meta("dynamic_decal", true)
    linear_damp = 0.4
    # Acero colgado: oscila segundos (medido wmax 0,54 rad/s con 9 mm).
    # El papel amortigua rapido; el acero no: damp comun lo mataba en ~0,8 s.
    angular_damp = 0.18 if kind == "steel" else 0.5
    _build_visuals()

    if kind == "paper":
        plate_height = 0.9
        plate_width = 0.66
        set_meta("surface", "paper")
        set_meta("penetrable", true)
    else:
        plate_height = 0.62
        plate_width = 0.62
        set_meta("surface", "steel")
        set_meta("penetrable", false)


func _build_visuals() -> void:
    if kind == "paper":
        base_material = StandardMaterial3D.new()
        base_material.albedo_texture = preload("res://assets/textures/target_paper.png")
        base_material.roughness = 0.95
        base_material.cull_mode = BaseMaterial3D.CULL_DISABLED
        var box := BoxMesh.new()
        box.size = Vector3(plate_width, plate_height, 0.004)
        box.material = base_material
        plate_mesh = MeshInstance3D.new()
        plate_mesh.mesh = box
        add_child(plate_mesh)

        var shape := BoxShape3D.new()
        shape.size = Vector3(plate_width, plate_height, 0.004)
        var collider := CollisionShape3D.new()
        collider.shape = shape
        add_child(collider)
    else:
        base_material = StandardMaterial3D.new()
        base_material.albedo_texture = preload("res://assets/textures/metal_albedo.png")
        base_material.metallic = 0.9
        base_material.roughness = 0.28
        var cylinder := CylinderMesh.new()
        cylinder.height = 0.022
        cylinder.top_radius = 0.31
        cylinder.bottom_radius = 0.31
        cylinder.radial_segments = 32
        cylinder.material = base_material
        plate_mesh = MeshInstance3D.new()
        plate_mesh.mesh = cylinder
        plate_mesh.rotation_degrees = Vector3(90, 0, 0)
        add_child(plate_mesh)

        var shape := CylinderShape3D.new()
        shape.height = 0.022
        shape.radius = 0.31
        var collider := CollisionShape3D.new()
        collider.shape = shape
        collider.rotation_degrees = Vector3(90, 0, 0)
        add_child(collider)
