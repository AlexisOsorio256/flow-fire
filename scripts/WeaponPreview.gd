extends Node3D

## Previsualizador del arma: instancia el MISMO Glock que usa el juego y lo
## fotografía desde varios ángulos, para revisar el acabado sin abrir una partida.
##
## Uso: godot4 --path . --scene res://scenes/WeaponPreview.tscn
## No pasar `--rendering-driver vulkan` a secas: puede forzar Forward+ y saltarse
## el renderer Mobile del proyecto. Si se compara un renderer, especificar también
## `--rendering-method` de forma explícita.
## Salida: /tmp/weapon_preview_<ángulo>.png

const GLOCK_SCRIPT := preload("res://scripts/Glock.gd")

# Ángulo -> posición de cámara (el arma se mira desde el origen).
const VIEWS := {
    "lado": Vector3(0.85, 0.10, 0.10),
    "tres_cuartos": Vector3(0.62, 0.30, -0.75),
    "trasera": Vector3(0.40, 0.34, -1.00),
    "detalle_corredera": Vector3(0.34, 0.26, -0.36),
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
    var names: Array[String] = []
    if gun.viewmodel.arms_root != null:
        var stack: Array = [gun.viewmodel.arms_root]
        while not stack.is_empty():
            var n = stack.pop_back()
            if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
                var tris := 0
                for si in range((n as MeshInstance3D).mesh.get_surface_count()):
                    var ar: Array = (n as MeshInstance3D).mesh.surface_get_arrays(si)
                    if ar.size() > 0 and ar[Mesh.ARRAY_INDEX] != null:
                        tris += (ar[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
                names.append("%s(%dtris)" % [n.name, tris])
            for c in n.get_children():
                stack.append(c)
    print("PREVIEW piezas: ", ", ".join(names))
    print("PREVIEW caja=", gun.viewmodel.gun_box.size, " usable=", gun.viewmodel.pistol_ok)
