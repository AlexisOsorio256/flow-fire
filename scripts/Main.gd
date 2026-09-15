extends Node3D

const WORLD_SCRIPT := preload("res://scripts/World.gd")
const PLAYER_SCRIPT := preload("res://scripts/Player.gd")
const HUD_SCRIPT := preload("res://scripts/HUD.gd")

var world: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var environment_node: WorldEnvironment


func _ready() -> void:
    randomize()
    _setup_environment()
    _build_world()
    _build_player()
    _build_hud()
    if OS.get_cmdline_user_args().has("--autotest"):
        _run_autotest()
    if OS.get_cmdline_user_args().has("--capture"):
        _run_capture()


func _setup_environment() -> void:
    environment_node = WorldEnvironment.new()
    environment_node.name = "WorldEnvironment"
    add_child(environment_node)

    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(0.16, 0.21, 0.30)
    sky_mat.sky_horizon_color = Color(0.42, 0.38, 0.34)
    sky_mat.ground_bottom_color = Color(0.025, 0.027, 0.032)
    sky_mat.ground_horizon_color = Color(0.18, 0.17, 0.16)
    sky.sky_material = sky_mat
    env.sky = sky

    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.45
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = 0.95
    env.adjustment_enabled = true
    env.adjustment_contrast = 1.08
    env.adjustment_saturation = 0.94
    env.ssao_enabled = true
    env.ssao_radius = 0.65
    env.ssao_intensity = 1.45
    env.ssil_enabled = false
    env.glow_enabled = true
    env.glow_intensity = 0.55
    env.glow_bloom = 0.08
    env.glow_hdr_threshold = 0.82
    env.fog_enabled = true
    env.fog_light_color = Color(0.08, 0.09, 0.11)
    env.fog_density = 0.008
    env.fog_sky_affect = 0.25
    env.volumetric_fog_enabled = false

    environment_node.environment = env


func _build_world() -> void:
    world = WORLD_SCRIPT.new()
    world.name = "World"
    add_child(world)
    world.build()


func _build_player() -> void:
    player = PLAYER_SCRIPT.new()
    player.name = "Player"
    add_child(player)
    player.global_position = Vector3(0, 0.05, 0)


func _build_hud() -> void:
    hud = HUD_SCRIPT.new()
    hud.name = "HUD"
    add_child(hud)
    hud.setup(player)


func _run_capture() -> void:
    await get_tree().create_timer(1.0).timeout
    var cam: Camera3D = player.camera
    var eye: Vector3 = cam.global_position
    var target_pos := Vector3(-4.0, 1.35, -18.0)
    var to_target: Vector3 = (target_pos - eye).normalized()
    player.yaw_target = atan2(-to_target.x, -to_target.z)
    player.pitch_target = asin(clampf(to_target.y, -1.0, 1.0))
    player.yaw = player.yaw_target
    player.pitch = player.pitch_target
    await get_tree().create_timer(0.35).timeout
    player.weapon.force_fire_once()
    await get_tree().create_timer(0.35).timeout
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    image.save_png("/tmp/godot_frame.png")
    print("CAPTURE saved /tmp/godot_frame.png ", image.get_size())
    get_tree().quit()


func _run_autotest() -> void:
    await get_tree().create_timer(0.6).timeout
    var cam: Camera3D = player.camera
    var eye: Vector3 = cam.global_position
    var target_pos := Vector3(-4.0, 1.35, -18.0)
    var to_target: Vector3 = (target_pos - eye).normalized()
    player.yaw_target = atan2(-to_target.x, -to_target.z)
    player.pitch_target = asin(clampf(to_target.y, -1.0, 1.0))
    player.yaw = player.yaw_target
    player.pitch = player.pitch_target
    await get_tree().create_timer(0.25).timeout
    player.weapon.force_fire_once()
    await get_tree().create_timer(1.0).timeout
    var targets := get_tree().get_nodes_in_group("targets")
    var health := -1.0
    if not targets.is_empty():
        health = targets[0].health
    print("AUTOTEST targets=", targets.size(), " first_health=", health, " ammo_mag=", player.weapon.mag, " chamber=", player.weapon.chamber, " fps=", Engine.get_frames_per_second())
    get_tree().quit()
