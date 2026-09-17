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
    if OS.get_cmdline_user_args().has("--aimtest"):
        _run_aimtest()
    if OS.get_cmdline_user_args().has("--pentest"):
        _run_pentest()
    if OS.get_cmdline_user_args().has("--penetrationdiag"):
        _run_penetrationdiag()
    if OS.get_cmdline_user_args().has("--reloadtest"):
        _run_reloadtest()
    _run_dev_tools()


## Comandos de diagnóstico y medida. El laboratorio vive en DevTools.gd (que
## reparte por responsabilidad) para que este archivo siga siendo el juego y sus
## tests. `--devhelp` lista todo lo disponible.
func _run_dev_tools() -> void:
    var tools := DEV_TOOLS.new()
    tools.name = "DevTools"
    add_child(tools)
    tools.setup(self, player, hud)
    tools.run(OS.get_cmdline_user_args())


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
    # El halo visible de las lámparas venía sobre todo de su luminancia y de
    # las Omni, no de una identidad bodycam que necesitase bloom abundante.
    # Conservamos un glow corto para las altas luces, pero evitamos lavar el
    # techo y los materiales cercanos.
    env.glow_intensity = 0.28
    env.glow_bloom = 0.04
    env.glow_hdr_threshold = 1.25
    # Los niveles 3 y 4 del glow aportaban una cola de blur muy suave: medido
    # sobre capturas idénticas, su ausencia sólo cambiaba ~1% de bloques 8x8
    # por encima de 4/255, pero costaban ~2.4 ms/frame en la GPU objetivo.
    # Se conserva el nivel 2, que es el que da el halo visible de la lente.
    env.set("glow_levels/3", 0.0)
    env.set("glow_levels/4", 0.0)
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


## Las dos recargas que existen, cada una con su contrato:
##  - en vacío (sin cartucho en recámara): hay que liberar la corredera, que
##    recámara un cartucho del cargador nuevo -> 16+1 y el total se conserva;
##  - táctica (con cartucho en recámara): el cargador se cambia pero la recámara
##    NO se toca y la corredera no se manipula; además la animación se corta
##    antes de ese gesto, así que la recarga es más corta.
func _run_reloadtest() -> void:
    await get_tree().create_timer(0.25).timeout
    var w = player.weapon
    var failures: Array[String] = []

    # --- recarga en vacío ---
    w.mag = 0
    w.chamber = 0
    w.reserve = 17
    w.slide_locked = true
    w.slide_pos = 0.039
    w.slide_vel = 0.0
    var empty_started: bool = w.start_reload()
    var empty_total: float = w.reload_total
    # La espera se deriva de la duracion real de la recarga (las animaciones del
    # rig nuevo duran mas que las antiguas): antes eran 2,65 s fijos y con un
    # total de 4,0 s la recarga seguia en curso al empezar la siguiente prueba.
    await get_tree().create_timer(empty_total + 0.6).timeout
    var empty_rounds: int = w.mag + w.chamber + w.reserve
    if not empty_started:
        failures.append("la recarga en vacío no arrancó")
    if w.reloading:
        failures.append("la recarga en vacío no terminó")
    if w.slide_locked:
        failures.append("la corredera siguió trabada tras recargar en vacío")
    if w.chamber != 1 or w.mag != 16:
        failures.append("recarga en vacío dejó mag=%d chamber=%d (esperado 16+1)" % [w.mag, w.chamber])
    if empty_rounds != 17:
        failures.append("la recarga en vacío no conservó la munición (%d cartuchos)" % empty_rounds)
    print("RELOADTEST vacia mag=", w.mag, " chamber=", w.chamber, " reserve=", w.reserve,
        " total=", empty_rounds, " reload_total=", snappedf(empty_total, 0.01))

    # --- recarga táctica (conservando la recámara) ---
    w.mag = 5
    w.chamber = 1
    w.reserve = 10
    w.slide_locked = false
    w.slide_pos = 0.0
    var tactical_started: bool = w.start_reload()
    var tactical_total: float = w.reload_total
    var tactical_empty: bool = w.reload_empty
    var slide_moved := false
    var guard := 0.0
    while w.reloading and guard < 6.0:
        await get_tree().process_frame
        guard += get_process_delta_time()
        if w.slide_locked or w.slide_pos > 0.004:
            slide_moved = true
    var tactical_rounds: int = w.mag + w.chamber + w.reserve
    if not tactical_started:
        failures.append("la recarga táctica no arrancó")
    if tactical_empty:
        failures.append("la recarga con recámara llena se marcó como recarga en vacío")
    if slide_moved:
        failures.append("la recarga táctica manipuló la corredera")
    if w.chamber != 1:
        failures.append("la recarga táctica perdió el cartucho de la recámara (chamber=%d)" % w.chamber)
    if w.mag != 15 or tactical_rounds != 16:
        failures.append("recarga táctica dejó mag=%d y %d cartuchos (esperado 15 y 16)" % [w.mag, tactical_rounds])
    if tactical_total >= empty_total:
        failures.append("la recarga táctica no es más corta que la de vacío (%.2f vs %.2f)" % [tactical_total, empty_total])
    print("RELOADTEST tactica mag=", w.mag, " chamber=", w.chamber, " reserve=", w.reserve,
        " total=", tactical_rounds, " reload_total=", snappedf(tactical_total, 0.01),
        " corredera_movida=", slide_moved)

    var passed := failures.is_empty()
    print("RELOADTEST passed=", passed)
    if not passed:
        push_error("RELOADTEST falló: " + "; ".join(failures))
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


## Dos tiros controlados contra volúmenes penetrables reales. El diagnóstico
## sólo pasa si cada tiro encuentra una segunda cara del collider: así vigila
## que no vuelva la antigua salida fabricada desde `thickness`.
func _run_penetrationdiag() -> void:
    await get_tree().create_timer(0.7).timeout
    var w = player.weapon
    w.mag = 5
    w.chamber = 1
    w.reserve = 10
    var before := Ballistics.penetration_events

    _aim_at(Vector3(-5.8, 1.08, -8.0))
    await get_tree().create_timer(0.2).timeout
    w.force_fire_once()
    await get_tree().create_timer(0.35).timeout

    _aim_at(Vector3(-8.6, 1.2, -14.0))
    await get_tree().create_timer(0.2).timeout
    w.force_fire_once()
    await get_tree().create_timer(0.45).timeout

    var exits := Ballistics.penetration_events - before
    var passed := exits >= 2
    print("PENETRATIONDIAG exits=", exits, " expected>=2 passed=", passed)
    if not passed:
        push_error("PENETRATIONDIAG falló: no se encontraron las dos caras de los paneles")
    get_tree().quit(0 if passed else 1)


func _run_aimtest() -> void:
    await get_tree().create_timer(0.7).timeout
    player.weapon.set_aim(true)
    await get_tree().create_timer(1.0).timeout
    # La autoridad es la mira visible: alza trasera Y delantera de la corredera
    # real (hijas del hueso Slidder) sobre el eje optico. La mira manda y la
    # pose de ADS la sigue (ver _solve_ads), asi que este test vigila el
    # producto real: si alguien mueve el arma, la mira o la pose de ADS, falla.
    var eye: Vector3 = player.camera.global_position
    var forward: Vector3 = -player.camera.global_transform.basis.z.normalized()
    var worst_mm := 0.0
    var worst_mrad := 0.0
    var idx := 0
    for sight in [player.weapon.viewmodel.get_sight_world_position(), player.weapon.viewmodel.get_front_sight_world_position()]:
        var to_sight: Vector3 = (sight - eye)
        var angle_mrad: float = acos(clampf(to_sight.normalized().dot(forward), -1.0, 1.0)) * 1000.0
        var offset_mm: float = tan(angle_mrad * 0.001) * to_sight.length() * 1000.0
        var glock_inv: Transform3D = (player.weapon as Node3D).global_transform.affine_inverse()
        var in_g: Vector3 = glock_inv * sight
        var eye_g: Vector3 = glock_inv * eye
        print("AIMTEST mira=", idx, " offset_mm=", snappedf(offset_mm, 0.1),
            " mrad=", snappedf(angle_mrad, 0.01), " en_glock=", in_g.snapped(Vector3(0.001, 0.001, 0.001)),
            " ojo_glock=", eye_g.snapped(Vector3(0.001, 0.001, 0.001)))
        idx += 1
        worst_mm = maxf(worst_mm, offset_mm)
        worst_mrad = maxf(worst_mrad, angle_mrad)
    # En headless el viewport es diminuto (32x32): el error angular no depende
    # de la resolución y sí dice si la mira está centrada.
    # La mira y el impacto tienen que coincidir: el desvío debe ser de
    # milímetros, no de un grado. La mira va en el centro de la pantalla porque
    # es ahí donde va la bala.
    const MAX_OFFSET_MM := 6.0
    const MAX_ANGLE_MRAD := 12.0
    var passed: bool = worst_mm <= MAX_OFFSET_MM and worst_mrad <= MAX_ANGLE_MRAD and player.weapon.aim_blend > 0.99
    print("AIMTEST peor_mira_mm=", snappedf(worst_mm, 0.1),
        " peor_mrad=", snappedf(worst_mrad, 0.01),
        " aim_blend=", player.weapon.aim_blend, " passed=", passed)
    if not passed:
        push_error("AIMTEST falló: alguna mira se desvía más de %d mm del centro" % int(MAX_OFFSET_MM))
    get_tree().quit(0 if passed else 1)


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
