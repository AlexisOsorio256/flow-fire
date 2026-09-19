extends Node3D

const WORLD_SCRIPT := preload("res://scripts/World.gd")
const PLAYER_SCRIPT := preload("res://scripts/Player.gd")
const HUD_SCRIPT := preload("res://scripts/HUD.gd")
const RANGE_SHELL_SCENE := preload("res://scenes/RangeShell.tscn")

var world: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var environment_node: WorldEnvironment

## Banderas de PERFILADO (ver `_perf_overrides`). No son opciones de juego.
var perf_no_shadows := false
var perf_no_lights := false
var perf_no_reflection := false
var perf_no_fog := false
var perf_no_glow := false
var perf_no_world := false
var perf_no_hud := false
var perf_no_bodycam := false
## Cuantas luces pueden proyectar sombra (perfilado). -1 = no tocar.
var perf_shadow_casters := -1


func _ready() -> void:
    randomize()
    _perf_overrides()
    _setup_environment()
    _build_range_shell()
    _build_world()
    _build_player()
    _build_hud()
    _apply_perf_overrides()


## Ajustes de PERFILADO, no de juego. Solo se activan por linea de comandos
## (`-- --no-shadows=1`) para poder medir el coste real de una luz, una sombra o
## un grupo de geometria sobre el frame time. En una partida normal no hay
## ninguna bandera y todo queda como lo deja el codigo.
func _perf_overrides() -> void:
    var args := OS.get_cmdline_user_args()
    for a in args:
        var kv := (a as String).split("=")
        if kv.size() != 2:
            continue
        match kv[0]:
            "--no-shadows":
                perf_no_shadows = kv[1] == "1"
            "--no-lights":
                perf_no_lights = kv[1] == "1"
            "--shadow-casters":
                perf_shadow_casters = int(kv[1])
            "--no-reflection":
                perf_no_reflection = kv[1] == "1"
            "--no-fog":
                perf_no_fog = kv[1] == "1"
            "--no-glow":
                perf_no_glow = kv[1] == "1"
            "--no-world":
                perf_no_world = kv[1] == "1"
            "--no-hud":
                perf_no_hud = kv[1] == "1"
            "--no-bodycam":
                perf_no_bodycam = kv[1] == "1"


## Aplica las banderas de perfilado ya con el arbol montado. Una sola pasada.
func _apply_perf_overrides() -> void:
    if perf_no_world and world != null:
        world.visible = false
        world.process_mode = Node.PROCESS_MODE_DISABLED
    if perf_no_hud and hud != null:
        hud.visible = false
    if perf_no_bodycam:
        # El shader bodycam es un efecto de pantalla completa: se apaga para
        # medir lo que cuesta de verdad.
        # El post bodycam es el ColorRect del HUD, no un nodo aparte: se apaga
        # su material para poder medir lo que cuesta el efecto de pantalla.
        if hud != null:
            var post: Variant = hud.get("post")
            if post != null and post is CanvasItem:
                (post as CanvasItem).visible = false
    if perf_no_reflection:
        for node in find_children("*", "ReflectionProbe", true, false):
            (node as ReflectionProbe).visible = false
    if perf_no_lights:
        for node in find_children("*", "Light3D", true, false):
            (node as Light3D).visible = false
    elif perf_no_shadows:
        for node in find_children("*", "Light3D", true, false):
            (node as Light3D).shadow_enabled = false
    elif perf_shadow_casters >= 0:
        var casters := find_children("*", "Light3D", true, false)
        for index in range(casters.size()):
            (casters[index] as Light3D).shadow_enabled = index < perf_shadow_casters
    if perf_no_fog or perf_no_glow:
        var env := environment_node.environment
        if perf_no_fog:
            env.fog_enabled = false
        if perf_no_glow:
            env.glow_enabled = false


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
    env.ambient_light_color = Color(0.62, 0.63, 0.68)
    env.ambient_light_energy = 1.45
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = 1.05
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
    player.global_position = Vector3(2.0, 0.05, 0.5)
    player.world = world


func _build_hud() -> void:
    hud = HUD_SCRIPT.new()
    hud.name = "HUD"
    add_child(hud)
    hud.setup(player)
