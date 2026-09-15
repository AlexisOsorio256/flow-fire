extends Node3D

## Previsualizador del arma: instancia el MISMO Glock que usa el juego (con sus
## materiales por primitiva y su alineación medida en runtime) y lo fotografía
## desde varios ángulos, para revisar el acabado sin abrir el juego.
##
## Uso: godot4 --path . --scene res://scenes/WeaponPreview.tscn --rendering-driver vulkan
## Salida: /tmp/weapon_preview_<ángulo>.png

const GLOCK_SCRIPT := preload("res://scripts/Glock.gd")

# Ángulo -> posición de cámara (el arma se mira desde el origen).
const VIEWS := {
    "lado": Vector3(0.30, 0.06, 0.02),
    "tres_cuartos": Vector3(0.24, 0.10, -0.22),
    "trasera": Vector3(0.16, 0.08, -0.30),
    "detalle_corredera": Vector3(0.16, 0.11, -0.10),
}

var camera: Camera3D
var gun


func _ready() -> void:
    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.10, 0.11, 0.13)
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.72, 0.76, 0.85)
    e.ambient_light_energy = 0.9
    e.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.environment = e
    add_child(env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-42.0, -52.0, 0.0)
    sun.light_energy = 2.2
    sun.shadow_enabled = true
    add_child(sun)

    var fill := OmniLight3D.new()
    fill.position = Vector3(0.35, 0.30, -0.45)
    fill.light_energy = 3.0
    fill.omni_range = 2.5
    add_child(fill)

    var rim := OmniLight3D.new()
    rim.position = Vector3(-0.30, 0.15, 0.35)
    rim.light_energy = 2.0
    rim.omni_range = 2.0
    rim.light_color = Color(0.75, 0.82, 1.0)
    add_child(rim)

    camera = Camera3D.new()
    camera.fov = 30.0
    camera.near = 0.01
    add_child(camera)
    camera.current = true

    # El arma real, tal cual se ve en el juego.
    gun = GLOCK_SCRIPT.new()
    gun.name = "Glock"
    add_child(gun)
    gun.setup(camera)
    gun.set_aim(false)
    gun.set_motion(0.0, Vector2.ZERO, Vector2.ZERO)

    await get_tree().create_timer(0.4).timeout
    await RenderingServer.frame_post_draw
    _print_measurements()
    for view_name in VIEWS:
        var offset: Vector3 = VIEWS[view_name]
        camera.position = offset
        camera.look_at(gun.global_position + Vector3(0.0, 0.0, 0.0), Vector3.UP)
        await RenderingServer.frame_post_draw
        await RenderingServer.frame_post_draw
        var image := get_viewport().get_texture().get_image()
        var path := "/tmp/weapon_preview_%s.png" % view_name
        image.save_png(path)
        print("PREVIEW ", view_name, " -> ", path)
    get_tree().quit()


func _print_measurements() -> void:
    var mesh: MeshInstance3D = gun.glock_mesh
    if mesh == null:
        print("PREVIEW sin malla")
        return
    var names: Array[String] = []
    for i in range(mesh.mesh.get_surface_count()):
        var mat := mesh.get_surface_override_material(i)
        names.append("%s=%s" % [mesh.mesh.surface_get_name(i), "shader" if mat is ShaderMaterial else str(mat)])
    print("PREVIEW materiales: ", ", ".join(names))
    print("PREVIEW largo_m=", snappedf((gun.mesh_to_weapon as Transform3D).basis.get_scale().x * 0.045424, 0.0001))
