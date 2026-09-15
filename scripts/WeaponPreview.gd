extends Node3D

const MODEL := preload("res://assets/models/glock_rigged.glb")


func _ready() -> void:
    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.045, 0.055, 0.07)
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.75, 0.78, 0.85)
    e.ambient_light_energy = 0.7
    e.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.environment = e
    add_child(env)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -38.0, 0.0)
    sun.light_energy = 1.6
    sun.shadow_enabled = true
    add_child(sun)

    var fill := OmniLight3D.new()
    fill.position = Vector3(-0.5, 0.35, 0.45)
    fill.light_energy = 2.0
    fill.omni_range = 3.0
    add_child(fill)

    var model := MODEL.instantiate()
    const LOCAL_LENGTH := 0.045424
    const DESIRED_LENGTH := 0.186
    const ARMATURE_SCALE := 48.2968
    var visual_scale := DESIRED_LENGTH / LOCAL_LENGTH
    var root_scale := visual_scale / ARMATURE_SCALE
    var target_basis := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
    model.transform.basis = target_basis.scaled(Vector3(root_scale, root_scale, root_scale))
    model.position = Vector3.ZERO
    add_child(model)

    var bullet_mesh := model.find_child("Glock19_001", true, false) as MeshInstance3D
    if bullet_mesh != null:
        bullet_mesh.visible = false

    var cam := Camera3D.new()
    add_child(cam)
    cam.position = Vector3(0.32, 0.10, 0.0)
    cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
    cam.fov = 34.0
    cam.current = true

    await get_tree().process_frame
    var mesh := model.find_child("Glock19", true, false) as MeshInstance3D
    if mesh != null:
        print("PREVIEW mesh scale=", mesh.global_transform.basis.get_scale(), " aabb=", mesh.get_aabb())
    var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
    if sk != null:
        print("PREVIEW skeleton scale=", sk.global_transform.basis.get_scale())
    await get_tree().create_timer(0.4).timeout
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    image.save_png("/tmp/weapon_preview.png")
    print("PREVIEW saved ", image.get_size())
    get_tree().quit()
