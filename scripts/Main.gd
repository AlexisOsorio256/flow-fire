extends Node3D

const WORLD_SCRIPT := preload("res://scripts/World.gd")
const PLAYER_SCRIPT := preload("res://scripts/Player.gd")
const HUD_SCRIPT := preload("res://scripts/HUD.gd")
const DEV_TOOLS := preload("res://scripts/DevTools.gd")

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
    if OS.get_cmdline_user_args().has("--aimtest"):
        _run_aimtest()
    if OS.get_cmdline_user_args().has("--pentest"):
        _run_pentest()
    if OS.get_cmdline_user_args().has("--reloadtest"):
        _run_reloadtest()
    _run_dev_tools()


## Comandos de diagnóstico (capturas, timeline, benchmark, medidas y audio).
## Están en DevTools.gd para que este archivo siga siendo el juego y sus tests.
func _run_dev_tools() -> void:
    var args := OS.get_cmdline_user_args()
    var tools := DEV_TOOLS.new()
    tools.name = "DevTools"
    add_child(tools)
    tools.setup(self, player, hud)
    if args.has("--fpsbench"):
        tools.run_fpsbench()
    if args.has("--probe"):
        tools.run_probe()
    if args.has("--geometrydebug"):
        tools.run_geometrydebug()
    if args.has("--timeline"):
        tools.run_timeline()
    if args.has("--shotcapture"):
        tools.run_shotcapture()
    if args.has("--audiocapture"):
        tools.run_audiocapture()


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
    env.ssao_enabled = false
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


func _run_reloadtest() -> void:
    await get_tree().create_timer(0.25).timeout
    # Estado de corredera abierta con un cargador vacío y exactamente 17 cartuchos de reserva.
    player.weapon.mag = 0
    player.weapon.chamber = 0
    player.weapon.reserve = 17
    player.weapon.slide_locked = true
    player.weapon.slide_pos = 0.039
    player.weapon.slide_vel = 0.0
    var started: bool = player.weapon.start_reload()
    await get_tree().create_timer(2.65).timeout
    var total_rounds: int = player.weapon.mag + player.weapon.chamber + player.weapon.reserve
    var passed: bool = started and not player.weapon.reloading and not player.weapon.slide_locked and player.weapon.chamber == 1 and player.weapon.mag == 16 and total_rounds == 17
    print("RELOADTEST passed=", passed, " mag=", player.weapon.mag, " chamber=", player.weapon.chamber, " reserve=", player.weapon.reserve, " total=", total_rounds, " slide=", player.weapon.slide_pos)
    if not passed:
        push_error("RELOADTEST falló: la recarga vacía no dejó 16+1 cartuchos conservando el total")
    get_tree().quit(0 if passed else 1)


func _run_pentest() -> void:
    await get_tree().create_timer(0.7).timeout
    _aim_at(Vector3(-4.0, 1.35, -18.0))
    await get_tree().create_timer(0.25).timeout

    var targets := get_tree().get_nodes_in_group("targets")
    var health_before := _first_target_health(targets)
    var decals_before: int = ImpactFX.decals.size()

    player.weapon.force_fire_once()
    await get_tree().create_timer(1.0).timeout

    var decals_after: int = ImpactFX.decals.size()
    var health_after := _first_target_health(targets)

    var failures: Array[String] = []
    if decals_after <= decals_before:
        failures.append("no se crearon orificios (%d -> %d)" % [decals_before, decals_after])
    if targets.is_empty():
        failures.append("no hay blancos en el grupo 'targets'")
    elif health_after >= health_before:
        failures.append("el blanco no recibió daño (%.1f -> %.1f)" % [health_before, health_after])

    var passed := failures.is_empty()
    print("PENTEST passed=", passed, " decals=", decals_before, "->", decals_after,
        " health=", health_before, "->", health_after,
        " mag=", player.weapon.mag, " chamber=", player.weapon.chamber)
    if not passed:
        push_error("PENTEST falló: " + "; ".join(failures))
    get_tree().quit(0 if passed else 1)


func _run_aimtest() -> void:
    await get_tree().create_timer(0.7).timeout
    player.weapon.set_aim(true)
    await get_tree().create_timer(1.0).timeout
    var eye: Vector3 = player.camera.global_position
    var sight: Vector3 = player.weapon.get_sight_world_position()
    var screen_pos: Vector2 = player.camera.unproject_position(sight)
    var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
    var delta: float = screen_pos.distance_to(center)
    # En headless el viewport es diminuto (32x32) y delta_px pierde valor: el
    # error angular no depende de la resolución y sí dice si la mira está centrada.
    var forward: Vector3 = -player.camera.global_transform.basis.z.normalized()
    var angle_mrad: float = acos(clampf((sight - eye).normalized().dot(forward), -1.0, 1.0)) * 1000.0
    var offset_mm: float = tan(angle_mrad * 0.001) * (sight - eye).length() * 1000.0
    # El arma se enmarca con la mira algo por debajo del centro a propósito
    # (ADS_SIGHT_DROP) para no tapar el punto de mira: el test comprueba que el
    # desvío no se va de esa tolerancia y que el ADS está asentado.
    const MAX_OFFSET_MM := 14.0
    const MAX_ANGLE_MRAD := 30.0
    var passed: bool = offset_mm <= MAX_OFFSET_MM and angle_mrad <= MAX_ANGLE_MRAD and player.weapon.aim_blend > 0.99
    print("AIMTEST sight_screen=", screen_pos, " center=", center, " delta_px=", delta,
        " angle_mrad=", snappedf(angle_mrad, 0.01), " offset_mm=", snappedf(offset_mm, 0.1),
        " aim_blend=", player.weapon.aim_blend, " passed=", passed)
    if not passed:
        push_error("AIMTEST falló: la mira se desvía más de %d mm del centro" % int(MAX_OFFSET_MM))
    get_tree().quit(0 if passed else 1)


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
    _aim_at(Vector3(-4.0, 1.35, -18.0))
    await get_tree().create_timer(0.25).timeout

    var targets := get_tree().get_nodes_in_group("targets")
    var health_before := _first_target_health(targets)
    var rounds_before: int = player.weapon.mag + player.weapon.chamber + player.weapon.reserve

    player.weapon.force_fire_once()
    await get_tree().create_timer(1.0).timeout

    var health_after := _first_target_health(targets)
    var rounds_after: int = player.weapon.mag + player.weapon.chamber + player.weapon.reserve

    var failures: Array[String] = []
    if targets.is_empty():
        failures.append("no hay blancos en el grupo 'targets'")
    elif health_after >= health_before:
        failures.append("el disparo no hizo daño (%.1f -> %.1f)" % [health_before, health_after])
    if rounds_after != rounds_before - 1:
        failures.append("munición inconsistente (%d -> %d, se esperaba gastar 1)" % [rounds_before, rounds_after])
    if player.weapon.chamber <= 0:
        failures.append("la recámara quedó vacía: no recamaró tras el disparo")
    if player.weapon.mag < 0:
        failures.append("cargador con munición negativa")

    var passed := failures.is_empty()
    print("AUTOTEST passed=", passed, " targets=", targets.size(),
        " health=", health_before, "->", health_after,
        " rondas=", rounds_before, "->", rounds_after,
        " mag=", player.weapon.mag, " chamber=", player.weapon.chamber,
        " fps=", Engine.get_frames_per_second())
    if not passed:
        push_error("AUTOTEST falló: " + "; ".join(failures))
    get_tree().quit(0 if passed else 1)


## Apunta la cámara del jugador a un punto del mundo (lo usan los tests).
func _aim_at(target_pos: Vector3) -> void:
    var eye: Vector3 = player.camera.global_position
    var to_target: Vector3 = (target_pos - eye).normalized()
    player.yaw_target = atan2(-to_target.x, -to_target.z)
    player.pitch_target = asin(clampf(to_target.y, -1.0, 1.0))
    player.yaw = player.yaw_target
    player.pitch = player.pitch_target


func _first_target_health(targets: Array) -> float:
    if targets.is_empty():
        return -1.0
    return targets[0].health