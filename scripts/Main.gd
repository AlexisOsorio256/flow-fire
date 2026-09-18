extends Node3D

const WORLD_SCRIPT := preload("res://scripts/World.gd")
const PLAYER_SCRIPT := preload("res://scripts/Player.gd")
const HUD_SCRIPT := preload("res://scripts/HUD.gd")
const RANGE_SHELL_SCENE := preload("res://scenes/RangeShell.tscn")

var world: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var environment_node: WorldEnvironment


func _ready() -> void:
    randomize()
    _setup_environment()
    _build_range_shell()
    _build_world()
    _build_player()
    _build_hud()


func _setup_environment() -> void:
    environment_node = WorldEnvironment.new()
    environment_node.name = "WorldEnvironment"
    add_child(environment_node)

    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(0.25, 0.32, 0.44)
    sky_mat.sky_horizon_color = Color(0.42, 0.38, 0.34)
    # Rebote del suelo: las normales hacia abajo (techo) muestrean este lado
    # del cielo; en negro el techo no se leia nunca.
    sky_mat.ground_bottom_color = Color(0.10, 0.10, 0.11)
    sky_mat.ground_horizon_color = Color(0.28, 0.27, 0.26)
    sky.sky_material = sky_mat
    env.sky = sky

    # Sala cerrada: el ambiente es COLOR controlado, no cielo. El cielo solo
    # alimenta reflejos; la luz la ponen las luminarias con caida real.
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.44, 0.43, 0.42)
    env.ambient_light_energy = 1.05
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = 1.1
    env.adjustment_enabled = true
    env.adjustment_contrast = 1.05
    env.adjustment_saturation = 1.0
    env.ssao_enabled = false
    env.ssil_enabled = false
    env.glow_enabled = true
    # El halo visible de las lámparas venía sobre todo de su luminancia y de
    # las Omni, no de una identidad bodycam que necesitase bloom abundante.
    # Conservamos un glow corto para las altas luces, pero evitamos lavar el
    # techo y los materiales cercanos.
    env.glow_intensity = 0.28
    env.glow_bloom = 0.04
    env.glow_hdr_threshold = 1.25
    # Los niveles 3 y 4 del glow son una cola de blur muy suave que cuesta GPU
    # sin aportar al halo visible de la lente. Se conserva el nivel 2.
    env.set("glow_levels/3", 0.0)
    env.set("glow_levels/4", 0.0)
    env.fog_enabled = true
    env.fog_light_color = Color(0.16, 0.16, 0.17)
    env.fog_density = 0.010
    env.fog_sky_affect = 0.25
    env.volumetric_fog_enabled = false

    environment_node.environment = env


func _build_world() -> void:
    world = WORLD_SCRIPT.new()
    world.name = "World"
    add_child(world)
    world.build()


func _build_range_shell() -> void:
    var shell := RANGE_SHELL_SCENE.instantiate()
    shell.name = "RangeShell"
    add_child(shell)


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
