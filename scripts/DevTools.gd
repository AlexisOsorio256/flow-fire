extends Node

## Comandos de diagnóstico y medida. Viven aparte de Main.gd a propósito: Main
## es el arranque del juego y sus cuatro tests; esto es el laboratorio (capturas,
## timeline, benchmark, medidas del arma y captura de audio). Así el juego sigue
## siendo pequeño y el laboratorio no se mezcla con él.
##
## Uso: godot4 --path . --rendering-driver vulkan -- --timeline
##      (ver README, sección de verificación)

const GLOCK_SCRIPT := preload("res://scripts/Glock.gd")

var _main: Node3D
var _player: CharacterBody3D
var _hud: CanvasLayer
var _timeline_fired := 0
var _hip_bbox := Rect2()          # caja del arma en pantalla con la pose de lista
var _mag_rest_box := AABB()       # caja del cargador en reposo, frame de arma
var _exposure_hip := {}           # exposición medida del arma en hip
var _exposure_ads := {}           # exposición medida del arma en ADS


func setup(main_node: Node3D, player_node: CharacterBody3D, hud_node: CanvasLayer) -> void:
    _main = main_node
    _player = player_node
    _hud = hud_node


## Medición de rendimiento A/B. No es un profiler genérico: es el banco
## mínimo para apagar/encender un subsistema cada vez sobre la misma escena,
## cámara, resolución, calentamiento y duración. Los toggles se aplican al
## estado vivo (no reconstruyen la escena) para que cualquier diferencia sea
## coste de frame, no coste de setup.
const BENCH_VARIANTS := [
    {"id": "base", "label": "baseline_completo"},
    {"id": "post_off", "label": "bodycam_post_off"},
    {"id": "glow_off", "label": "glow_off"},
    {"id": "fog_off", "label": "fog_off"},
    {"id": "stage_omnis_off", "label": "luces_omni_interior_off"},
    {"id": "dir_shadow_off", "label": "sombra_direccional_off"},
    {"id": "vm_lights_off", "label": "luces_viewmodel_off"},
    {"id": "viewmodel_off", "label": "viewmodel_oculto"},
    {"id": "fx_off", "label": "impact_fx_off"},
]
const BENCH_DEFAULT_REPEATS := 2
const BENCH_DEFAULT_WARMUP := 1.0
const BENCH_DEFAULT_DURATION := 6.0

var _bench_stage_omnis: Array[OmniLight3D] = []
var _bench_viewmodel_lights: Array[OmniLight3D] = []
var _bench_sun: DirectionalLight3D
var _bench_stress := false
var _bench_capture := false
var _bench_stress_accum := 0.0
var _bench_stress_spawned := 0


func run_fpsbench() -> void:
    # Sin vsync: en headless el viewport es diminuto y con vsync la medida se
    # queda clavada en la frecuencia del monitor. La ventana real manda.
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    _bench_lock_viewport()
    _bench_bind_nodes()
    _bench_stress = OS.get_cmdline_user_args().has("--fpsstress")
    _bench_capture = OS.get_cmdline_user_args().has("--fpscapture")
    var cfg := _bench_options()
    var variants: Array = _bench_filter_variants(str(cfg["only"]))
    if variants.is_empty():
        print("FPSBENCH sin variantes para only=", cfg["only"])
        get_tree().quit(1)
        return

    print("FPSBENCH_V2 viewport=", get_viewport().get_visible_rect().size,
        " vsync=off warmup=", cfg["warmup"], "s duration=", cfg["duration"],
        "s repeats=", cfg["repeats"], " variants=", variants.size(),
        " only=", cfg["only"], " fx_stress=", _bench_stress,
        " captures=", _bench_capture)

    # Calentamiento global: compila shaders del escenario base y estabiliza
    # GPU/cachés antes de que la primera variante empiece a contar.
    _bench_apply_variant("base")
    await _bench_wait(float(cfg["warmup"]) + 1.0)

    var runs := {}
    var repeats := int(cfg["repeats"])
    for repeat in range(repeats):
        var ordered := _bench_rotate(variants, repeat * 3)
        for entry in ordered:
            var id: String = entry["id"]
            _bench_apply_variant(id)
            await _bench_wait(float(cfg["warmup"]))
            var stats: Dictionary = await _bench_measure(float(cfg["duration"]))
            if _bench_capture and repeat == 0:
                await _bench_capture_frame(id)
            if not runs.has(id):
                runs[id] = []
            runs[id].append(stats)
            _bench_print_run(repeat + 1, repeats, entry, stats)

    _bench_stress = false
    ImpactFX.spawning_enabled = true
    _bench_apply_variant("base")
    _bench_print_summary(variants, runs)
    get_tree().quit()


## Fija el viewport al tamaño de diseño del proyecto (1920x1080). Sin esto,
## según cómo el WM decore/recorte la ventana, benchmarks sucesivos medirían
## 1920x1008 o 1920x1080 y no serían comparables.
func _bench_lock_viewport() -> void:
    DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
    var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
    var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
    DisplayServer.window_set_size(Vector2i(width, height))
    DisplayServer.window_set_position(Vector2i.ZERO)


func _bench_options() -> Dictionary:
    var opts := {
        "repeats": BENCH_DEFAULT_REPEATS,
        "warmup": BENCH_DEFAULT_WARMUP,
        "duration": BENCH_DEFAULT_DURATION,
        "only": "",
    }
    for arg in OS.get_cmdline_user_args():
        if not arg.begins_with("--fps"):
            continue
        var parts := arg.split("=")
        if parts.size() != 2:
            continue
        match parts[0]:
            "--fpsreps":
                opts["repeats"] = maxi(1, int(parts[1]))
            "--fpswarmup":
                opts["warmup"] = maxf(0.1, float(parts[1]))
            "--fpsduration":
                opts["duration"] = maxf(0.5, float(parts[1]))
            "--fpsvariant":
                opts["only"] = parts[1]
    return opts


func _bench_filter_variants(only: String) -> Array:
    var wanted := {}
    if only != "":
        for raw in only.split(","):
            wanted[raw.strip_edges()] = true
    var result: Array = []
    for entry in BENCH_VARIANTS:
        if wanted.is_empty() or wanted.has(entry["id"]):
            result.append(entry)
    return result


func _bench_rotate(entries: Array, offset: int) -> Array:
    var result: Array = []
    var n := entries.size()
    if n == 0:
        return result
    var start := posmod(offset, n)
    for i in range(n):
        result.append(entries[(start + i) % n])
    return result


func _bench_bind_nodes() -> void:
    _bench_stage_omnis.clear()
    _bench_viewmodel_lights.clear()
    _bench_sun = null
    if _main.world != null:
        for child in _main.world.get_children():
            if child is OmniLight3D:
                _bench_stage_omnis.append(child)
            elif child is DirectionalLight3D:
                _bench_sun = child
    if _player.weapon != null and _player.weapon.pose_root != null:
        for child in _player.weapon.pose_root.get_children():
            if child is OmniLight3D:
                _bench_viewmodel_lights.append(child)
    print("FPSBENCH_BIND stage_omnis=", _bench_stage_omnis.size(),
        " vm_lights=", _bench_viewmodel_lights.size(),
        " sun=", _bench_sun != null)


## Deja SIEMPRE todos los subsistemas en estado baseline y apaga sólo la
## variante pedida. Así ninguna medición hereda el toggle anterior.
func _bench_apply_variant(variant_id: String) -> void:
    ImpactFX.spawning_enabled = variant_id != "fx_off"
    _bench_stress_accum = 0.0
    _bench_stress_spawned = 0
    var env: Environment = _main.environment_node.environment
    _hud.post.visible = variant_id != "post_off"
    env.glow_enabled = variant_id != "glow_off"
    env.fog_enabled = variant_id != "fog_off"
    var stage_on := variant_id != "stage_omnis_off"
    for light in _bench_stage_omnis:
        light.visible = stage_on
    if _bench_sun != null:
        _bench_sun.shadow_enabled = variant_id != "dir_shadow_off"
    var vm_lights_on := variant_id != "vm_lights_off"
    for light in _bench_viewmodel_lights:
        light.visible = vm_lights_on
    _player.weapon.visible = variant_id != "viewmodel_off"


## Guarda una captura del estado exacto de la variante, a la misma resolución
## y cámara que el benchmark, para poder revisar que la optimización no cambió
## la imagen más de lo aceptable.
##
## La escena se congela antes de capturar: sin eso las capturas del benchmark NO
## son comparables entre sí. Medido con el banco anterior: base contra fx_off
## (que cuesta 0.08 ms y no cambia nada visible) daba 6.3/255 de diferencia
## media y 36.6% de píxeles por encima de 4/255, todo ello balanceo del arma y
## respiración de la cámara entre una variante y la siguiente.
func _bench_capture_frame(variant_id: String) -> void:
    var dir := ProjectSettings.globalize_path("res://captures/fpsbench")
    DirAccess.make_dir_recursive_absolute(dir)
    var weapon_visible: bool = _player.weapon.visible
    await _freeze_scene("hip")
    _player.weapon.visible = weapon_visible
    var path := "%s/%s.png" % [dir, variant_id]
    await _capture_view(path)
    print("FPSBENCH_CAPTURE ", path)


func _bench_wait(seconds: float) -> void:
    var start := Time.get_ticks_usec()
    while float(Time.get_ticks_usec() - start) / 1000000.0 < seconds:
        await get_tree().process_frame
        _bench_stress_frame(get_process_delta_time())


## Estrés de FX sintético pero medible: impactos periódicos en un punto fijo
## delante de la cámara. No toca la lógica del arma ni de los blancos; existe
## sólo para que fx_off tenga un coste real que apagar. Se activa con
## --fpsstress y se mantiene idéntico para todas las variantes.
func _bench_stress_frame(delta: float) -> void:
    if not _bench_stress:
        return
    _bench_stress_accum += delta
    var interval := 0.18
    while _bench_stress_accum >= interval:
        _bench_stress_accum -= interval
        var cam: Camera3D = _player.camera
        var forward := -cam.global_transform.basis.z.normalized()
        var angle := float(_bench_stress_spawned) * 0.7
        var point := cam.global_position + forward * 2.4
        point += cam.global_transform.basis.x * (0.55 * cos(angle))
        point += cam.global_transform.basis.y * (0.26 * sin(angle))
        ImpactFX.spawn_impact(point, forward, null, "metal")
        _bench_stress_spawned += 1


## Devuelve frametimes reales entre frames de proceso. Se descartan los tres
## primeros para no contaminar con el cambio de estado/compilación de pipeline.
func _bench_measure(seconds: float) -> Dictionary:
    for _i in range(3):
        await get_tree().process_frame
    var samples: Array[float] = []
    var start_us := Time.get_ticks_usec()
    var last_us := start_us
    while true:
        await get_tree().process_frame
        var now_us := Time.get_ticks_usec()
        var dt := float(now_us - last_us) / 1000000.0
        last_us = now_us
        _bench_stress_frame(dt)
        samples.append(dt)
        if float(now_us - start_us) / 1000000.0 >= seconds:
            break
    return _bench_stats(samples)


func _bench_stats(samples: Array) -> Dictionary:
    var sorted: Array = samples.duplicate()
    sorted.sort()
    var n := sorted.size()
    if n == 0:
        return {"frames": 0, "elapsed": 0.0, "fps_avg": 0.0, "fps_min": 0.0,
            "fps_p1": 0.0, "frame_avg_ms": 0.0, "frame_p50_ms": 0.0,
            "frame_p95_ms": 0.0, "frame_max_ms": 0.0, "samples": []}
    var total := 0.0
    for dt in sorted:
        total += float(dt)
    var avg := total / float(n)
    var p50 := float(sorted[clampi(int(float(n) * 0.50), 0, n - 1)])
    var p95 := float(sorted[clampi(int(float(n) * 0.95), 0, n - 1)])
    var max_dt := float(sorted[n - 1])
    return {
        "frames": n,
        "elapsed": total,
        "fps_avg": 1.0 / maxf(avg, 0.000001),
        "fps_min": 1.0 / maxf(max_dt, 0.000001),
        "fps_p1": 1.0 / maxf(p95, 0.000001),
        "frame_avg_ms": avg * 1000.0,
        "frame_p50_ms": p50 * 1000.0,
        "frame_p95_ms": p95 * 1000.0,
        "frame_max_ms": max_dt * 1000.0,
        "samples": samples,
    }


func _bench_print_run(run_index: int, run_total: int, entry: Dictionary, stats: Dictionary) -> void:
    print("BENCH_RUN ", entry["id"], " ", entry["label"],
        " run=", run_index, "/", run_total,
        " frames=", stats["frames"],
        " fps_avg=", snappedf(stats["fps_avg"], 0.01),
        " fps_min=", snappedf(stats["fps_min"], 0.01),
        " fps_p1=", snappedf(stats["fps_p1"], 0.01),
        " frame_avg_ms=", snappedf(stats["frame_avg_ms"], 0.01),
        " frame_p50_ms=", snappedf(stats["frame_p50_ms"], 0.01),
        " frame_p95_ms=", snappedf(stats["frame_p95_ms"], 0.01),
        " frame_max_ms=", snappedf(stats["frame_max_ms"], 0.01))


func _bench_print_summary(variants: Array, runs: Dictionary) -> void:
    var baseline: Dictionary = {}
    for entry in variants:
        var id: String = entry["id"]
        var pooled: Array[float] = []
        for run_stats in runs.get(id, []):
            pooled.append_array(run_stats["samples"])
        var stats := _bench_stats(pooled)
        if id == "base":
            baseline = stats
        print("BENCH_SUMMARY ", id, " ", entry["label"],
            " runs=", runs.get(id, []).size(),
            " frames=", stats["frames"],
            " fps_avg=", snappedf(stats["fps_avg"], 0.01),
            " fps_min=", snappedf(stats["fps_min"], 0.01),
            " fps_p1=", snappedf(stats["fps_p1"], 0.01),
            " frame_avg_ms=", snappedf(stats["frame_avg_ms"], 0.01),
            " frame_p50_ms=", snappedf(stats["frame_p50_ms"], 0.01),
            " frame_p95_ms=", snappedf(stats["frame_p95_ms"], 0.01),
            " frame_max_ms=", snappedf(stats["frame_max_ms"], 0.01))
    if not baseline.is_empty():
        for entry in variants:
            var id: String = entry["id"]
            if id == "base":
                continue
            var pooled: Array[float] = []
            for run_stats in runs.get(id, []):
                pooled.append_array(run_stats["samples"])
            var stats := _bench_stats(pooled)
            var gain_fps: float = stats["fps_avg"] - float(baseline["fps_avg"])
            var gain_pct: float = gain_fps / maxf(float(baseline["fps_avg"]), 0.001) * 100.0
            var save_ms: float = float(baseline["frame_avg_ms"]) - float(stats["frame_avg_ms"])
            print("BENCH_DELTA ", id,
                " vs_base_fps=", snappedf(gain_fps, 0.01),
                " pct=", snappedf(gain_pct, 0.1),
                " frame_save_ms=", snappedf(save_ms, 0.01))


## ---------------------------------------------------------------------------
## Banco visual A/B determinista.
##
## Para decidir si un cambio de renderer degrada la imagen no basta con mirar
## dos capturas del juego: tienen que ser LA MISMA imagen salvo por lo que se
## compara. En FlowFire eso no ocurre por defecto, porque hay cuatro fuentes de
## variación entre dos corridas cualesquiera:
##
##  1. el balanceo/retroceso del arma y la respiración de la cámara avanzan con
##     el reloj, así que la pose y el encuadre cambian de una captura a otra;
##  2. la animación del autor mueve los brazos y el cargador por su cuenta;
##  3. el fogonazo enciende una luz con energía aleatoria, que alumbra la escena
##     entera de forma distinta cada vez;
##  4. el grano del bodycam usa el reloj del sistema como semilla.
##
## Aquí las cuatro se clavan: time_scale 0, fases y resortes a cero, animación
## posicionada en un tiempo exacto, energía del fogonazo fija y semilla del
## grano constante. Dos corridas del mismo estado —en el mismo renderer o en
## otro— dan la misma imagen, así que cualquier diferencia que quede es del
## cambio que se está evaluando.
##
## Uso: godot4 --path . --rendering-driver vulkan -- --visualab
##      --visualout=captures/visual/fp  --visualonly=hip,ads
## ---------------------------------------------------------------------------
const VISUAL_STATES := ["env", "hip", "ads", "shot", "casing", "reload", "slide_back"]

# Estado de referencia: quieto, mirando al frente, sin retroceso ni respiración.
const VISUAL_YAW := 0.0
const VISUAL_PITCH := 0.0
const VISUAL_EYE_Y := 1.62
const VISUAL_FOV_HIP := 82.0
const VISUAL_FOV_ADS := 60.0
const VISUAL_GRAIN_TIME := 12.0        # semilla fija del grano del bodycam
const VISUAL_FLASH_ENERGY := 8.0       # energía fija del fogonazo
const VISUAL_LOADOUT := {"mag": 17, "chamber": 1, "reserve": 68}

var _visual_pin := {}
var _visual_pin_active := false


func run_visualab() -> void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    _bench_lock_viewport()
    var out_dir := _visual_out_dir()
    DirAccess.make_dir_recursive_absolute(out_dir)
    var wanted := _visual_filter()
    print("VISUALAB dir=", out_dir, " viewport=", get_viewport().get_visible_rect().size,
        " gpu=", RenderingServer.get_video_adapter_name(),
        " metodo=", RenderingServer.get_current_rendering_method(),
        " driver=", RenderingServer.get_current_rendering_driver_name(),
        " setting=", ProjectSettings.get_setting("rendering/renderer/rendering_method", "<sin definir>"),
        " estados=", wanted)
    await get_tree().create_timer(1.2).timeout
    # El HUD se coloca una vez y se apaga: su _process reescribe el reloj y los
    # FPS cada segundo y esos textos sí cambian entre corridas.
    _hud.set_process(false)
    _hud.fps_label.visible = false
    _hud.clock_label.visible = false
    # Prioridad alta: este nodo procesa DESPUÉS del arma y del HUD, así que sus
    # fijaciones son la última escritura antes de dibujar. El arma reescribe la
    # energía del fogonazo con randf en cada _process, de modo que fijarla desde
    # fuera de ese orden no servía de nada (medido: quedaba un 17.7% de píxeles
    # distintos entre dos corridas idénticas, todo él sobre el arma).
    set_process_priority(100)
    set_process(true)
    for state in wanted:
        await _freeze_scene(state)
        var path := "%s/%s.png" % [out_dir, state]
        await _capture_view(path)
        print("VISUALAB_CAPTURE ", state, " -> ", path)
    set_process(false)
    _visual_pin_active = false
    Engine.time_scale = 1.0
    _hud.set_process(true)
    _hud.fps_label.visible = true
    _hud.clock_label.visible = true
    _player.weapon.set_process(true)
    _player.set_process(true)
    print("VISUALAB_DONE")
    get_tree().quit()


## Última escritura de cada frame mientras dura una captura: vuelve a clavar lo
## que el propio juego randomiza por frame.
func _process(_delta: float) -> void:
    if not _visual_pin_active:
        return
    var w = _player.weapon
    if w.muzzle_light != null:
        w.muzzle_light.light_energy = float(_visual_pin["flash_energy"])
    _hud.post_mat.set_shader_parameter("time", float(_visual_pin["post_time"]))
    _hud.post_mat.set_shader_parameter("aim_amount", float(_visual_pin["aim_amount"]))
    _hud.post_mat.set_shader_parameter("exposure_pulse", float(_visual_pin["shot_pulse"]))


func _visual_out_dir() -> String:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--visualout="):
            return ProjectSettings.globalize_path("res://" + arg.split("=", true, 1)[1])
    return ProjectSettings.globalize_path("res://captures/visual")


func _visual_filter() -> Array:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--visualonly="):
            var result: Array = []
            for raw in arg.split("=", true, 1)[1].split(","):
                var id := raw.strip_edges()
                if VISUAL_STATES.has(id):
                    result.append(id)
                else:
                    push_error("Estado visual desconocido: " + id)
            return result
    return VISUAL_STATES.duplicate()


## Congela la escena en un estado reproducible y deja todo listo para capturar.
func _freeze_scene(state: String) -> void:
    _visual_pin_active = false
    Engine.time_scale = 0.0
    _player.set_process(false)
    _visual_reset_player()
    _visual_reset_weapon()
    _visual_clear_shells()
    await get_tree().process_frame
    _visual_apply_state(state)
    # Dos frames: el primero asienta la pose de huesos, el segundo la dibuja.
    await get_tree().process_frame
    await get_tree().process_frame
    _visual_pin_post(state)


## Deja cámara y jugador en el mismo sitio y con la misma orientación en todas
## las capturas: sin esto el encuadre cambia entre corridas por la respiración.
func _visual_reset_player() -> void:
    var p = _player
    p.global_position = Vector3(0.0, 0.05, 0.0)
    p.velocity = Vector3.ZERO
    p.prev_velocity = Vector3.ZERO
    p.current_speed = 0.0
    p.current_move_norm = 0.0
    p.bob_phase = 0.0
    p.step_accum = 0.0
    p.breath_phase = 0.0
    p.bob_x = 0.0
    p.bob_y = 0.0
    p.bob_roll = 0.0
    p.body_lag = Vector3.ZERO
    p.lean = 0.0
    p.cam_y = VISUAL_EYE_Y
    p.cam_y_vel = 0.0
    p.yaw = VISUAL_YAW
    p.yaw_target = VISUAL_YAW
    p.pitch = VISUAL_PITCH
    p.pitch_target = VISUAL_PITCH
    p.yaw_vel = 0.0
    p.pitch_vel = 0.0
    p.look_delta = Vector2.ZERO
    p.sprinting = false
    p.crouching = false
    p.recoil_pitch = 0.0
    p.recoil_pitch_vel = 0.0
    p.recoil_yaw = 0.0
    p.recoil_yaw_vel = 0.0
    p.recoil_roll = 0.0
    p.recoil_roll_vel = 0.0
    p.recoil_kick = 0.0
    p.recoil_kick_vel = 0.0
    p.camera.position = Vector3(0.0, VISUAL_EYE_Y, 0.0)
    p.camera.rotation = Vector3.ZERO
    p.camera.fov = VISUAL_FOV_HIP


func _visual_reset_weapon() -> void:
    var w = _player.weapon
    w.player_speed = 0.0
    w.player_velocity = Vector3.ZERO
    w.look_delta = Vector2.ZERO
    w._last_local_move = Vector2.ZERO
    w.sway = Vector2.ZERO
    w.bob_phase = 0.0
    w.idle_phase = 0.0
    w.sprinting = false
    w.sprint_blend = 0.0
    w.aim = false
    w.aim_blend = 0.0
    w.trigger_held = false
    w.trigger_ready = true
    w.trigger_latched = false
    w.trigger_visual = 0.0
    w.recoil_pos = Vector3.ZERO
    w.recoil_vel = Vector3.ZERO
    w.recoil_rot = Vector3.ZERO
    w.recoil_rot_vel = Vector3.ZERO
    w.arm_recoil_pos = Vector3.ZERO
    w.arm_recoil_vel = Vector3.ZERO
    w.arm_recoil_rot = Vector3.ZERO
    w.arm_recoil_rot_vel = Vector3.ZERO
    w.muzzle_timer = 0.0
    w.shot_pulse = 0.0
    w.reloading = false
    w.reload_elapsed = 0.0
    w.reload_total = 0.0
    w.reload_empty = false
    w.reload_pose_blend = 0.0
    w.reload_mag_seated = true
    w.reload_anim_cut = true
    w.mag_sound_out = true
    w.slide_pos = 0.0
    w.slide_vel = 0.0
    w.slide_locked = false
    w.slide_open = false
    w.slide_extracted = true   # el casquillo lo coloca el estado, nunca el azar
    w.mag = int(VISUAL_LOADOUT["mag"])
    w.chamber = int(VISUAL_LOADOUT["chamber"])
    w.reserve = int(VISUAL_LOADOUT["reserve"])
    w.visible = true
    w._emit_ammo()


func _visual_apply_state(state: String) -> void:
    var w = _player.weapon
    _visual_park_animation("Idle", 0.0)
    match state:
        "env":
            w.visible = false
        "hip":
            pass
        "ads":
            w.aim_blend = 1.0
            _player.camera.fov = VISUAL_FOV_ADS
        "shot":
            # Instante del fogonazo: la corredera acaba de arrancar y aún no ha
            # abierto el puerto. Es el frame que ve el jugador al disparar.
            w.aim_blend = 1.0
            _player.camera.fov = VISUAL_FOV_ADS
            w.muzzle_timer = 0.04
            w.shot_pulse = 1.0
            w.slide_pos = 0.010
            w.trigger_visual = 1.0
            w.muzzle_flash.rotation.z = 0.0
            w.muzzle_flash.scale = Vector3.ONE
            w.muzzle_flash_2.rotation.z = 0.0
            w.muzzle_flash_2.scale = Vector3.ONE * 0.92
            _visual_park_animation("Shoot", 0.05)
        "casing":
            # Vaina en vuelo, puerto ya abierto: es el frame en el que el
            # casquillo se ve salir.
            w.aim_blend = 1.0
            _player.camera.fov = VISUAL_FOV_ADS
            w.slide_pos = GLOCK_SCRIPT.SLIDE_EJECT_AT + 0.006
            w.trigger_visual = 1.0
            _visual_place_shell()
            _visual_park_animation("Shoot", 0.12)
        "reload":
            # Recarga táctica a media maniobra: cargador fuera y arma levantada.
            w.reloading = true
            w.reload_elapsed = 0.85
            w.reload_empty = false
            w.mag = 5
            w.chamber = 1
            w.reserve = 51
            w._emit_ammo()
            _visual_park_animation("Reload", 0.85)
        "slide_back":
            # Corredera retenida atrás: enseña el puerto, el cañón y la recámara
            # sin el resto de la maniobra. Es la vista que delata la geometría.
            w.aim_blend = 1.0
            _player.camera.fov = VISUAL_FOV_ADS
            w.slide_locked = true
            w.mag = 0
            w.chamber = 0
            w.reserve = 51
            w._emit_ammo()
        _:
            push_error("Estado visual sin implementar: " + state)


## Coloca la animación del autor en un tiempo exacto y la deja ahí. Con
## time_scale 0 no avanza, así que la pose de brazos es la misma en cada corrida.
func _visual_park_animation(anim_name: String, t: float) -> void:
    var w = _player.weapon
    if w.animation_player == null:
        return
    var resolved: String = w._resolve_animation(anim_name)
    if resolved == "":
        return
    w.animation_player.play(resolved)
    w.animation_player.seek(t, true)


## Vaina en una posición de vuelo fija. La trayectoria real dura milisegundos y
## arranca con randf; para comparar renderers hace falta que las dos capturas
## tengan la vaina exactamente en el mismo punto, con el mismo giro.
func _visual_place_shell() -> void:
    var w = _player.weapon
    w._spawn_shell()
    var shells := get_tree().get_nodes_in_group("shells")
    if shells.is_empty():
        return
    var shell = shells[shells.size() - 1]
    if shell is RigidBody3D:
        shell.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
        shell.freeze = true
        shell.linear_velocity = Vector3.ZERO
        shell.angular_velocity = Vector3.ZERO
    var port: Transform3D = w.ejection_port.global_transform
    var offset := Vector3(0.055, 0.042, 0.018)
    var spin := Basis(Vector3(0.35, 0.9, 0.25).normalized(), 1.15)
    shell.global_transform = Transform3D(port.basis * spin, port * offset)


func _visual_clear_shells() -> void:
    for shell in get_tree().get_nodes_in_group("shells"):
        shell.queue_free()


## Clava los parámetros del post que dependen del reloj o de randf, para que el
## bodycam pinte el mismo grano y la misma exposición en todas las capturas.
## No se aplica aquí: se guarda y lo reaplica _process en cada frame, después de
## que el arma haya vuelto a randomizar lo suyo.
func _visual_pin_post(state: String) -> void:
    var w = _player.weapon
    var t := VISUAL_GRAIN_TIME
    if state == "shot":
        t += 0.02
    elif state == "casing":
        t += 0.04
    _visual_pin = {
        "flash_energy": VISUAL_FLASH_ENERGY if w.muzzle_timer > 0.0 else 0.0,
        "post_time": t,
        "aim_amount": w.aim_blend,
        "shot_pulse": w.shot_pulse,
    }
    _visual_pin_active = true
    _process(0.0)


## Espera a que la pose del arma se asiente (la transición hip<->ADS tarda ~0.5 s
## y medir a mitad da números falsos).
func _settle_pose() -> void:
    for _i in range(200):
        await get_tree().process_frame
        var w = _player.weapon
        if absf(w.aim_blend - (1.0 if w.aim else 0.0)) < 0.01 and w.sprint_blend < 0.01:
            break


func _capture_view(path: String) -> void:
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    image.save_png(path)


func _probe_state(state_name: String) -> void:
    Engine.time_scale = 0.0
    _hud.post.visible = false
    await get_tree().process_frame
    await get_tree().process_frame
    await _capture_view("/tmp/probe_%s_with.png" % state_name)
    _player.weapon.visible = false
    await get_tree().process_frame
    await get_tree().process_frame
    await _capture_view("/tmp/probe_%s_without.png" % state_name)
    _player.weapon.visible = true
    _hud.post.visible = true
    Engine.time_scale = 1.0
    print("PROBE ", state_name, " listo")


func run_probe() -> void:
    await get_tree().create_timer(0.8).timeout
    _player.weapon.set_aim(false)
    await _probe_state("hip")
    _player.weapon.set_aim(true)
    await get_tree().create_timer(0.6).timeout
    await _probe_state("ads")
    # Fogonazo: time_scale queda en 0, así que se congela en el frame del disparo.
    _player.weapon.force_fire_once()
    await _probe_state("shot")
    _player.weapon.set_aim(false)
    await get_tree().create_timer(0.2).timeout
    _force_reloadable_state()
    _player.weapon.start_reload()
    await get_tree().create_timer(0.75).timeout
    await _probe_state("reload")
    print("PROBE_DONE")
    get_tree().quit()


## Timeline de capturas: graba una secuencia guionizada (quieto, caminando,
## apuntar, disparos y recarga) guardando un frame cada 0.1 s con sus métricas,
## para revisar el arma con los ojos en vez de suponer.
## Uso: godot4 --path . --rendering-driver vulkan -- --timeline
func run_timeline() -> void:
    var dir := ProjectSettings.globalize_path("res://captures/timeline")
    DirAccess.make_dir_recursive_absolute(dir)
    print("TIMELINE dir=", dir)
    await get_tree().create_timer(1.0).timeout
    _player.weapon.reserve = 34
    _timeline_fired = 0
    var step := 0.1
    var index := 0
    while index * step < 6.6:
        var t := index * step
        _timeline_drive(t)
        await get_tree().create_timer(step).timeout
        await _capture_view("%s/frame_%03d.png" % [dir, index])
        _print_timeline_metrics(index, t)
        index += 1
    print("TIMELINE_DONE frames=", index, " dir=", dir)
    get_tree().quit()


## Guion: hip quieto -> caminando -> ADS -> dos disparos -> recarga.


func _timeline_drive(t: float) -> void:
    var w = _player.weapon
    if t < 1.0:
        _player.current_speed = 0.0
        w.set_motion(0.0, Vector2.ZERO, Vector2.ZERO)
        w.set_aim(false)
    elif t < 2.0:
        _player.current_speed = 4.0
        w.set_motion(4.0, Vector2(0.0, 1.0), Vector2.ZERO)
        w.set_aim(false)
    elif t < 4.2:
        _player.current_speed = 0.0
        w.set_motion(0.0, Vector2.ZERO, Vector2.ZERO)
        w.set_aim(true)
        if t > 2.9 and _timeline_fired == 0:
            _timeline_fired = 1
            print("TL_FIRE 1 can_fire=", w.chamber, "/", w.mag, "/", w.slide_pos)
            w.force_fire_once()
        elif t > 3.3 and _timeline_fired == 1:
            _timeline_fired = 2
            print("TL_FIRE 2 can_fire=", w.chamber, "/", w.mag, "/", w.slide_pos)
            w.force_fire_once()
        elif t > 4.1 and _timeline_fired == 2:
            _timeline_fired = 3
            # Solo aquí se vacía el arma: si no, los disparos anteriores no salen.
            _force_reloadable_state()
            w.start_reload()
    else:
        w.set_aim(false)


func _print_timeline_metrics(index: int, t: float) -> void:
    var cam: Camera3D = _player.camera
    var w = _player.weapon
    var center := get_viewport().get_visible_rect().size * 0.5
    var sight_px := cam.unproject_position(w.get_sight_world_position())
    var muzzle_px := cam.unproject_position(w.muzzle.global_position)
    var world_from_bind: Transform3D = (w.recoil_node as Node3D).global_transform * (w.mesh_to_weapon as Transform3D)
    var box := _bind_aabb(w.glock_mesh)
    var bbox := _screen_bbox(box, world_from_bind, cam)
    print("TL %03d t=%.1f aim=%.2f mag=%.0f cham=%.0f sight=(%.0f,%.0f) dy_sight=%.0f muzzle=(%.0f,%.0f) gun_top=%.0f gun_bottom=%.0f gun_h=%.0f slide=%.3f reload=%s" % [
        index, t, w.aim_blend, w.mag, w.chamber,
        sight_px.x, sight_px.y, sight_px.y - center.y,
        muzzle_px.x, muzzle_px.y,
        bbox["min"].y, bbox["max"].y, bbox["size"].y,
        w.slide_pos, str(w.reloading)
    ])
    print("TL_CAM %03d pitch_deg=%.1f pitch_target_deg=%.1f roll_deg=%.1f recoil_pitch=%.3f yaw_deg=%.1f pos_y=%.2f" % [
        index, rad_to_deg(_player.pitch), rad_to_deg(_player.pitch_target), rad_to_deg(_player.camera.rotation.z),
        _player.recoil_pitch, rad_to_deg(_player.yaw), _player.global_position.y
    ])


func _screen_bbox(verts_box: AABB, world_transform: Transform3D, camera_node: Camera3D) -> Dictionary:
    var cmin := verts_box.position
    var cmax := verts_box.position + verts_box.size
    var smin := Vector2(1e9, 1e9)
    var smax := Vector2(-1e9, -1e9)
    for xi in [0.0, 1.0]:
        for yi in [0.0, 1.0]:
            for zi in [0.0, 1.0]:
                var corner := Vector3(
                    lerpf(cmin.x, cmax.x, xi),
                    lerpf(cmin.y, cmax.y, yi),
                    lerpf(cmin.z, cmax.z, zi)
                )
                var sp := camera_node.unproject_position(world_transform * corner)
                smin.x = minf(smin.x, sp.x); smin.y = minf(smin.y, sp.y)
                smax.x = maxf(smax.x, sp.x); smax.y = maxf(smax.y, sp.y)
    return {"min": smin, "max": smax, "size": smax - smin}


func run_geometrydebug() -> void:
    await get_tree().create_timer(0.8).timeout
    _player.weapon.set_aim(false)
    await _settle_pose()
    _print_geometry("hip")
    _exposure_hip = await _measure_gun_exposure("hip")
    _player.weapon.set_aim(true)
    await _settle_pose()
    _print_geometry("ads")
    _exposure_ads = await _measure_gun_exposure("ads")
    _player.weapon.set_aim(false)
    await get_tree().create_timer(0.4).timeout
    var travel := _print_bone_travel()
    var cycle := _measure_slide_cycle()
    # Durante la recarga: recorrido real del cargador y estado de los huesos.
    _force_reloadable_state()
    _player.weapon.start_reload()
    await get_tree().create_timer(0.45).timeout
    _print_geometry("reload")
    _print_live_bones("reload")
    var mag: Dictionary = await _measure_reload_mag()
    _finish_geometrydebug(travel, cycle, mag)


## Comprueba las medidas del arma: si deja de medirse o alinearse bien, el
## comando falla (es el ojo que vigila la alineación medida en runtime).


## Deja el arma en un estado que sí admite recarga: con el cargador lleno
## start_reload() no hace nada y las capturas de "recarga" saldrían falsas.
func _force_reloadable_state() -> void:
    _player.weapon.mag = 0
    _player.weapon.chamber = 0
    _player.weapon.reserve = 17


## Posición viva de los huesos (pose actual, no la de reposo) en frame de arma.


func _print_live_bones(label: String) -> void:
    var w = _player.weapon
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    var skeleton_node: Skeleton3D = w.skeleton
    for bone_name in ["Slide", "Magazine", "Trigger", "Barrel"]:
        var idx: int = skeleton_node.find_bone(bone_name)
        if idx < 0:
            continue
        var live: Vector3 = recoil_inv * (skeleton_node.global_transform * skeleton_node.get_bone_global_pose(idx).origin)
        print("LIVE ", label, " ", bone_name, " pose=", live.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " slide_pos=", snappedf(w.slide_pos, 0.0001))


## Comprueba que la corredera y el cargador viajan en la dirección medida: la
## corredera hacia atrás (+Z) y el cargador hacia abajo (-Y), en frame de arma.


func _print_bone_travel() -> Dictionary:
    var w = _player.weapon
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    w.slide_pos = w.SLIDE_TRAVEL
    w._apply_bone_poses()
    var deltas := {}
    for bone_name in ["Slide"]:
        var idx: int = (w.skeleton as Skeleton3D).find_bone(bone_name)
        if idx < 0:
            continue
        var posed: Vector3 = recoil_inv * ((w.skeleton as Skeleton3D).global_transform * (w.skeleton as Skeleton3D).get_bone_global_pose(idx).origin)
        var rest: Vector3 = recoil_inv * ((w.skeleton as Skeleton3D).global_transform * (w.skeleton as Skeleton3D).get_bone_global_rest(idx).origin)
        deltas[bone_name] = posed - rest
        print("TRAVEL ", bone_name, " rest=", rest.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " posed=", posed.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " delta=", (posed - rest).snapped(Vector3(0.0001, 0.0001, 0.0001)))
    w.slide_pos = 0.0
    w._apply_bone_poses()
    return deltas


## Recorrido máximo del cargador durante una recarga real, medido en vivo: lo
## mueve la animación del autor, así que hay que muestrear mientras ocurre.
func _measure_reload_mag() -> Dictionary:
    var w = _player.weapon
    var bone: int = (w.skeleton as Skeleton3D).find_bone("Magazine")
    if bone < 0:
        return {}
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    var rest: Vector3 = recoil_inv * ((w.skeleton as Skeleton3D).global_transform * (w.skeleton as Skeleton3D).get_bone_global_rest(bone).origin)
    var max_travel := 0.0
    var at := 0.0
    var on_screen := 0
    var best_margin := -1e9
    var viewport := get_viewport().get_visible_rect().size
    var cam: Camera3D = _player.camera
    for _i in range(26):
        await get_tree().create_timer(0.1).timeout
        var world: Vector3 = (w.skeleton as Skeleton3D).global_transform * (w.skeleton as Skeleton3D).get_bone_global_pose(bone).origin
        var live: Vector3 = recoil_inv * world
        var travel := (live - rest).length()
        if travel > max_travel:
            max_travel = travel
            at = w.reload_elapsed
        # Lo que importa de verdad: que el cargador se VEA salir y entrar. Se
        # proyecta el hueso y se cuenta cuánto tiempo está dentro del encuadre.
        if not cam.is_position_behind(world):
            var screen := cam.unproject_position(world)
            var margin := minf(minf(screen.x, viewport.x - screen.x), minf(screen.y, viewport.y - screen.y))
            best_margin = maxf(best_margin, margin)
            if margin > 20.0:
                on_screen += 1
    print("RELOAD_MAG recorrido_max=", snappedf(max_travel, 0.001), " m en t=", snappedf(at, 0.01),
        " s muestras_en_pantalla=", on_screen, "/26 margen_max=", snappedf(best_margin, 0.1), "px")
    return {"travel": max_travel, "on_screen": on_screen}


func _print_geometry(label: String) -> void:
    var cam: Camera3D = _player.camera
    var w = _player.weapon
    var mesh: MeshInstance3D = w.glock_mesh
    if mesh == null:
        print("GEOMETRY ", label, " mesh=null")
        return
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    # La geometría visible la coloca la cadena medida (mesh_to_weapon), no el
    # transform del nodo de malla: el AABB de bind hay que pasarlo por ahí.
    var world_from_bind: Transform3D = (w.recoil_node as Node3D).global_transform * (w.mesh_to_weapon as Transform3D)
    var box := _bind_aabb(mesh)
    var bbox := _screen_bbox(box, world_from_bind, cam)
    var box_weapon := _transform_aabb(box, w.mesh_to_weapon)
    var sight_screen: Vector2 = cam.unproject_position(w.get_sight_world_position())
    var muzzle_screen: Vector2 = cam.unproject_position(w.muzzle.global_position)
    var sight_cam: Vector3 = cam.global_transform.affine_inverse() * w.get_sight_world_position()
    var muzzle_cam: Vector3 = cam.global_transform.affine_inverse() * w.muzzle.global_position
    var pm: Vector3 = recoil_inv * (w.muzzle as Node3D).global_position
    var pe: Vector3 = recoil_inv * (w.ejection_port as Node3D).global_position
    var ps: Vector3 = recoil_inv * w.get_sight_world_position()
    var frame: Basis = (w.gun_frame_bind as Basis).orthonormalized()
    print("FRAME ", label, " bind_euler=", frame.get_euler().snapped(Vector3(0.001, 0.001, 0.001)),
        " bind_det=", snappedf(frame.determinant(), 0.001),
        " mesh_to_weapon=", (w.mesh_to_weapon as Transform3D).basis.orthonormalized().get_euler().snapped(Vector3(0.001, 0.001, 0.001)),
        " escala=", (w.mesh_to_weapon as Transform3D).basis.get_scale().snapped(Vector3(0.001, 0.001, 0.001)))
    print("GUNBOX ", label,
        " min=", box_weapon.position.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " size=", box_weapon.size.snapped(Vector3(0.0001, 0.0001, 0.0001)))
    if w.skeleton != null:
        for bone_name in ["Root", "Slide", "Trigger", "Magazine", "Barrel", "SlideCatch"]:
            var bi: int = (w.skeleton as Skeleton3D).find_bone(bone_name)
            if bi >= 0:
                var gp: Transform3D = (w.skeleton as Skeleton3D).global_transform * (w.skeleton as Skeleton3D).get_bone_global_rest(bi)
                var rel: Vector3 = recoil_inv * gp.origin
                print("BONE ", label, " ", bone_name, " rel=", rel.snapped(Vector3(0.0001, 0.0001, 0.0001)))
    print("AXES ", label,
        " sight_local=", ps.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " muzzle_local=", pm.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " eject_local=", pe.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " barrel_dir=", (pm - ps).normalized().snapped(Vector3(0.001, 0.001, 0.001)))
    print("GEOMETRY ", label,
        " bbox_min=", bbox["min"].snapped(Vector2(0.1, 0.1)),
        " bbox_max=", bbox["max"].snapped(Vector2(0.1, 0.1)),
        " bbox_size=", bbox["size"].snapped(Vector2(0.1, 0.1)),
        " sight_screen=", sight_screen.snapped(Vector2(0.1, 0.1)),
        " muzzle_screen=", muzzle_screen.snapped(Vector2(0.1, 0.1)),
        " sight_cam=", sight_cam.snapped(Vector3(0.001, 0.001, 0.001)),
        " muzzle_cam=", muzzle_cam.snapped(Vector3(0.001, 0.001, 0.001)),
        " viewport=", get_viewport().get_visible_rect().size)
    if label == "hip":
        _hip_bbox = Rect2(bbox["min"], bbox["size"])


## Cuánta luz recibe de verdad el arma en pantalla. El arma se aísla por
## diferencia (captura con y sin ella) para que la medida no la contamine el
## fondo: devuelve la luminancia media de sus píxeles, el percentil 90, cuántos
## están recortados a blanco y cuántos a negro.
func _measure_gun_exposure(label: String) -> Dictionary:
    Engine.time_scale = 0.0
    await get_tree().process_frame
    await get_tree().process_frame
    var with_gun := await _capture_image()
    _player.weapon.visible = false
    await get_tree().process_frame
    await get_tree().process_frame
    var without := await _capture_image()
    _player.weapon.visible = true
    Engine.time_scale = 1.0
    if with_gun == null or without == null:
        print("EXPOSURE ", label, " sin captura")
        return {}
    with_gun.convert(Image.FORMAT_RGB8)
    without.convert(Image.FORMAT_RGB8)
    var a := with_gun.get_data()
    var b := without.get_data()
    var width := with_gun.get_width()
    var height := with_gun.get_height()
    var samples := PackedFloat32Array()
    var total := 0
    var sum := 0.0
    var bright := 0
    var dark := 0
    var step := 2
    for y in range(0, height, step):
        for x in range(0, width, step):
            var i := (y * width + x) * 3
            var dr := absi(a[i] - b[i])
            var dg := absi(a[i + 1] - b[i + 1])
            var db := absi(a[i + 2] - b[i + 2])
            if dr + dg + db < 6:
                continue
            var luma := (a[i] * 0.299 + a[i + 1] * 0.587 + a[i + 2] * 0.114) / 255.0
            samples.append(luma)
            sum += luma
            total += 1
            if luma > 0.96:
                bright += 1
            if luma < 0.03:
                dark += 1
    if total == 0:
        print("EXPOSURE ", label, " el arma no ocupa ningún píxel")
        return {}
    samples.sort()
    var result := {
        "pixels": total,
        "mean": sum / float(total),
        "p90": samples[int(float(total) * 0.90)],
        "blown": float(bright) / float(total),
        "black": float(dark) / float(total),
    }
    print("EXPOSURE ", label, " px=", total,
        " media=", snappedf(result["mean"] * 255.0, 0.1), "/255",
        " p90=", snappedf(result["p90"] * 255.0, 0.1),
        " recortado=", snappedf(result["blown"] * 100.0, 0.1), "%",
        " negro=", snappedf(result["black"] * 100.0, 0.1), "%")
    return result


func _capture_image() -> Image:
    await RenderingServer.frame_post_draw
    return get_viewport().get_texture().get_image()


## Mide el ciclo REAL de la corredera usando el integrador del juego (no una
## copia): se dispara el impulso de un tiro y se avanza el subpaso con dt fijo
## hasta que vuelve a batería. Devuelve recorrido máximo y tiempos, que son el
## contrato de "la corredera se ve viajar".
func _measure_slide_cycle() -> Dictionary:
    var w = _player.weapon
    w.slide_pos = 0.0
    w.slide_vel = 0.0
    w.slide_locked = false
    w.slide_open = false
    w.slide_extracted = false
    w.slide_vel += w.SLIDE_IMPULSE  # mismo impulso que _fire()
    var dt := 0.001
    var peak := 0.0
    var t_total := 0.0
    var t_above := 0.0
    var came_back := false
    for i in range(400):
        w._update_slide(dt)
        var t := float(i) * dt
        peak = maxf(peak, w.slide_pos)
        if w.slide_pos > 0.025:
            t_above += dt
        if i > 4 and w.slide_pos < 0.002 and not came_back:
            came_back = true
            t_total = t
    if not came_back:
        t_total = 0.4
    w.slide_pos = 0.0
    w.slide_vel = 0.0
    var result := {"peak": peak, "total": t_total, "above": t_above}
    print("SLIDECYCLE recorrido_max=", snappedf(peak * 1000.0, 0.1), " mm",
        " ciclo_total=", snappedf(t_total * 1000.0, 1), " ms",
        " sobre_25mm=", snappedf(t_above * 1000.0, 1), " ms")
    return result


func _bind_aabb(mesh: MeshInstance3D) -> AABB:
    var result := AABB()
    var first := true
    for surface in range(mesh.mesh.get_surface_count()):
        var arrays := mesh.mesh.surface_get_arrays(surface)
        if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
            continue
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        for v in verts:
            if first:
                result = AABB(v, Vector3.ZERO)
                first = false
            else:
                result = result.expand(v)
    return result


func _transform_aabb(box: AABB, transform: Transform3D) -> AABB:
    var cmin := box.position
    var cmax := box.position + box.size
    var result := AABB()
    var first := true
    for xi in [0.0, 1.0]:
        for yi in [0.0, 1.0]:
            for zi in [0.0, 1.0]:
                var corner := Vector3(
                    lerpf(cmin.x, cmax.x, xi),
                    lerpf(cmin.y, cmax.y, yi),
                    lerpf(cmin.z, cmax.z, zi)
                )
                var p := transform * corner
                if first:
                    result = AABB(p, Vector3.ZERO)
                    first = false
                else:
                    result = result.expand(p)
    return result


func _finish_geometrydebug(travel: Dictionary, cycle: Dictionary, mag: Dictionary) -> void:
    var w = _player.weapon
    var failures: Array[String] = []
    if not w.alignment_ok:
        failures.append("la alineación medida del arma no verifica")
    if absf(w.measured_length_m - 0.186) > 0.002:
        failures.append("largo medido %.4f m (esperado 0.186)" % w.measured_length_m)
    var size: Vector3 = w.gun_box.size
    if absf(size.x - 0.0296) > 0.003 or absf(size.y - 0.1286) > 0.004 or absf(size.z - 0.186) > 0.003:
        failures.append("caja del arma %s (esperado ~0.0296 x 0.1286 x 0.186)" % size)
    var slide: Vector3 = travel.get("Slide", Vector3.ZERO)
    if slide.z < 0.02:
        failures.append("la corredera no viaja hacia atrás (delta %s)" % slide)
    if float(mag.get("travel", 0.0)) < 0.08:
        failures.append("el cargador casi no se separa del arma al recargar (%.3f m)" % float(mag.get("travel", 0.0)))
    if int(mag.get("on_screen", 0)) < 3:
        failures.append("el cargador no llega a verse en pantalla al recargar (%d/26 muestras)" % int(mag.get("on_screen", 0)))

    # Encuadre: el arma tiene que caber en pantalla con la pose de lista. Antes
    # quedaban 264 px por debajo del borde y sólo se veía media corredera.
    var viewport := get_viewport().get_visible_rect().size
    if _hip_bbox.size.y < 1.0:
        failures.append("no se midió el encuadre del arma")
    else:
        var top_frac := _hip_bbox.position.y / viewport.y
        var visible := (minf(_hip_bbox.end.y, viewport.y) - maxf(_hip_bbox.position.y, 0.0)) / maxf(_hip_bbox.size.y, 1.0)
        var right_frac := _hip_bbox.end.x / viewport.x
        var left_frac := _hip_bbox.position.x / viewport.x
        var centre_frac := (_hip_bbox.position.x + _hip_bbox.size.x * 0.5) / viewport.x
        if _hip_bbox.position.y < 0.24 * viewport.y:
            failures.append("el arma tapa el centro de la pantalla (y=%.0f de %.0f)" % [_hip_bbox.position.y, viewport.y])
        if top_frac > 0.74:
            failures.append("el arma está demasiado baja: su borde superior cae en y=%.0f (%.0f%% de la pantalla)" % [_hip_bbox.position.y, top_frac * 100.0])
        if visible < 0.94:
            failures.append("sólo se ve el %.0f%% del arma en pose de lista" % (visible * 100.0))
        if right_frac > 1.02:
            failures.append("el arma se sale por la derecha (x=%.0f de %.0f)" % [_hip_bbox.end.x, viewport.x])
        if left_frac < -0.02:
            failures.append("el arma se sale por la izquierda (x=%.0f)" % _hip_bbox.position.x)
        # Centrado: el arma va en el centro del encuadre, no desplazada a un lado.
        if absf(centre_frac - 0.5) > 0.09:
            failures.append("el arma no va centrada: su centro cae en el %.0f%% del ancho" % (centre_frac * 100.0))

    # Exposición: ni silueta negra ni mancha recortada.
    for entry in [["hip", _exposure_hip], ["ads", _exposure_ads]]:
        var label: String = entry[0]
        var data: Dictionary = entry[1]
        if data.is_empty():
            failures.append("no se pudo medir la exposición del arma en %s" % label)
            continue
        if data["mean"] * 255.0 < 14.0:
            failures.append("el arma está sin luz en %s (media %.1f/255)" % [label, data["mean"] * 255.0])
        if data["p90"] * 255.0 < 38.0:
            failures.append("el arma no tiene zonas claras en %s (p90 %.1f/255)" % [label, data["p90"] * 255.0])
        if data["blown"] > 0.02:
            failures.append("brillo especular recortado en %s (%.1f%% de sus píxeles)" % [label, data["blown"] * 100.0])

    # Ciclo de corredera: recorrido completo y legible.
    if not cycle.is_empty():
        if cycle["peak"] < 0.0385 or cycle["peak"] > 0.041:
            failures.append("la corredera no completa su recorrido (%.1f mm)" % (cycle["peak"] * 1000.0))
        if cycle["above"] < 0.025:
            failures.append("la corredera pasa demasiado rápido por el fondo (%.1f ms sobre 25 mm)" % (cycle["above"] * 1000.0))
        if cycle["total"] < 0.07 or cycle["total"] > 0.17:
            failures.append("el ciclo de corredera es demasiado lento (%.0f ms)" % (cycle["total"] * 1000.0))

    var passed := failures.is_empty()
    var view := get_viewport().get_visible_rect().size
    print("ENCUADRE hip_centro_x=", snappedf((_hip_bbox.position.x + _hip_bbox.size.x * 0.5) / view.x * 100.0, 0.1),
        "% del ancho, ancho=", snappedf(_hip_bbox.size.x / view.x * 100.0, 0.1), "%",
        " alto=", snappedf(_hip_bbox.size.y / view.y * 100.0, 0.1), "%",
        " borde_sup=", snappedf(_hip_bbox.position.y / view.y * 100.0, 0.1), "%")
    print("GEOMETRYDEBUG passed=", passed, " largo_m=", snappedf(w.measured_length_m, 0.0001),
        " caja=", size.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " slide=", slide.snapped(Vector3(0.001, 0.001, 0.001)),
        " cargador=", snappedf(float(mag.get("travel", 0.0)), 0.001), " m visible=", int(mag.get("on_screen", 0)), "/26")
    if not passed:
        push_error("GEOMETRYDEBUG falló: " + "; ".join(failures))
    get_tree().quit(0 if passed else 1)


## Captura en cámara lenta del disparo y de la recarga: el ciclo de la corredera
## dura ~78 ms y a 10-14 FPS cabe entero entre dos frames, así que en la timeline
## nunca se ve. Aquí se baja time_scale para que cada frame renderizado avance
## ~6 ms de juego y se guardan los frames con sus métricas (corredera, casquillo,
## retroceso y cargador, este último medido sobre su geometría proyectada).
## Uso: godot4 --path . --rendering-driver vulkan -- --slowmo
func run_slowmo() -> void:
    await _slowmo_shot()
    await _slowmo_reload()
    Engine.time_scale = 1.0
    get_tree().quit()


func _slowmo_shot() -> void:
    var dir := ProjectSettings.globalize_path("res://captures/shot")
    DirAccess.make_dir_recursive_absolute(dir)
    await get_tree().create_timer(1.0).timeout
    _player.weapon.set_aim(true)
    await get_tree().create_timer(0.9).timeout
    var w = _player.weapon
    w.force_fire_once()
    Engine.time_scale = 0.08
    var frames := 26
    var above_10 := 0
    var above_25 := 0
    var shell_frames := 0
    var shell_px := 0.0
    var shell_first := Vector2.ZERO
    var peak_back := 0.0
    var peak_pitch := 0.0
    for i in range(frames):
        await get_tree().process_frame
        await _capture_view("%s/shot_%03d.png" % [dir, i])
        var cam: Camera3D = _player.camera
        # Cada capa del retroceso se mide por separado: no deben ser el mismo
        # movimiento disfrazado.
        var back: float = w.recoil_pos.z
        var pitch := rad_to_deg(w.recoil_rot.x)
        var arm_back: float = w.arm_recoil_pos.z
        var arm_pitch := rad_to_deg(w.arm_recoil_rot.x)
        peak_back = maxf(peak_back, back)
        peak_pitch = maxf(peak_pitch, pitch)
        if w.slide_pos > 0.010:
            above_10 += 1
        if w.slide_pos > 0.025:
            above_25 += 1
        var shells := get_tree().get_nodes_in_group("shells")
        var shell_text := "sin_casquillo"
        for shell in shells:
            var pos: Vector3 = (shell as Node3D).global_position
            var screen := cam.unproject_position(pos)
            var behind := cam.is_position_behind(pos)
            var edge := cam.unproject_position(pos + cam.global_transform.basis.x * 0.0057)
            var size_px := screen.distance_to(edge) * 2.0
            if not behind:
                shell_frames += 1
                shell_px = maxf(shell_px, size_px)
                if shell_first == Vector2.ZERO:
                    shell_first = screen
                shell_text = "casquillo pantalla=(%.0f,%.0f) tam=%.0fpx" % [screen.x, screen.y, size_px]
            else:
                shell_text = "casquillo detrás de cámara"
        print("SHOT %02d slide=%.1fmm arma(retro=%.1fmm cabeceo=%.2f°) brazos(retro=%.1fmm cabeceo=%.2f°) camara=%.2f° %s" % [
            i, w.slide_pos * 1000.0, back * 1000.0, pitch, arm_back * 1000.0, arm_pitch,
            rad_to_deg(_player.recoil_pitch), shell_text])
    Engine.time_scale = 1.0
    print("SHOTCAPTURE frames=", frames, " corredera>10mm=", above_10, " >25mm=", above_25,
        " frames_con_casquillo=", shell_frames, " casquillo_max_px=", snappedf(shell_px, 0.1),
        " primer_casquillo=", shell_first, " retroceso_max=", snappedf(peak_back * 1000.0, 1.0), "mm",
        " cabeceo_max=", snappedf(peak_pitch, 2.0), " dir=", dir)
    Engine.time_scale = 1.0
    await get_tree().create_timer(0.4).timeout





## Caja del cargador en pantalla, medida sobre su GEOMETRÍA: se toma su caja de
## reposo en frame de arma y se le aplica la transformación RELATIVA del hueso
## Magazine, conjugada al frame del arma (el esqueleto y el arma no comparten
## ejes: sin conjugar, la medida sale donde no está el cargador).
func _mag_screen_box() -> Dictionary:
    var w = _player.weapon
    var bone: int = (w.skeleton as Skeleton3D).find_bone("Magazine")
    if bone < 0:
        return {}
    if _mag_rest_box.size == Vector3.ZERO:
        var verts := PackedVector3Array()
        var mesh: MeshInstance3D = w.glock_mesh
        for i in range(mesh.mesh.get_surface_count()):
            if mesh.mesh.surface_get_name(i) != "Magazine":
                continue
            for v in mesh.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
                verts.append((w.mesh_to_weapon as Transform3D) * v)
        if verts.is_empty():
            return {}
        _mag_rest_box = _bounds_of(verts)
    var skeleton_node: Skeleton3D = w.skeleton
    var skel_from_weapon: Transform3D = ((w.model_root as Node3D).transform *
        _chain_to(w.skeleton, w.model_root)).affine_inverse()
    var weapon_from_skel: Transform3D = skel_from_weapon.affine_inverse()
    var rel_skel: Transform3D = skeleton_node.get_bone_global_pose(bone) * skeleton_node.get_bone_global_rest(bone).affine_inverse()
    var rel_weapon: Transform3D = weapon_from_skel * rel_skel * skel_from_weapon
    var posed: AABB = _transform_aabb(_mag_rest_box, (w.recoil_node as Node3D).global_transform * rel_weapon)
    var cam: Camera3D = _player.camera
    var sbox := Rect2()
    var first := true
    var cmin := posed.position
    var cmax := posed.position + posed.size
    for xi in [0.0, 1.0]:
        for yi in [0.0, 1.0]:
            for zi in [0.0, 1.0]:
                var corner := Vector3(lerpf(cmin.x, cmax.x, xi), lerpf(cmin.y, cmax.y, yi), lerpf(cmin.z, cmax.z, zi))
                if cam.is_position_behind(corner):
                    return {}
                var sp := cam.unproject_position(corner)
                if first:
                    sbox = Rect2(sp, Vector2.ZERO)
                    first = false
                else:
                    sbox = sbox.expand(sp)
    return {"box": sbox, "centro": cam.unproject_position(posed.position + posed.size * 0.5)}


func _bounds_of(verts: PackedVector3Array) -> AABB:
    if verts.is_empty():
        return AABB()
    var mn := verts[0]
    var mx := verts[0]
    for v in verts:
        mn = mn.min(v)
        mx = mx.max(v)
    return AABB(mn, mx - mn)


func _chain_to(node: Node, ancestor: Node) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current := node
    while current != null and current != ancestor:
        if current is Node3D:
            result = (current as Node3D).transform * result
        current = current.get_parent()
    return result


func _slowmo_reload() -> void:
    var dir := ProjectSettings.globalize_path("res://captures/reload")
    DirAccess.make_dir_recursive_absolute(dir)
    var w = _player.weapon
    w.set_aim(false)
    await get_tree().create_timer(0.6).timeout
    _force_reloadable_state()
    w.start_reload()
    # 0.35 de escala: cada frame renderizado avanza ~30 ms, así que 60 frames
    # cubren la recarga entera (2.11 s) sin perder el momento del cargador.
    Engine.time_scale = 0.35
    var frames := 60
    var visible_samples := 0
    var biggest := 0.0
    for i in range(frames):
        await get_tree().process_frame
        await _capture_view("%s/reload_%03d.png" % [dir, i])
        var sbox: Dictionary = _mag_screen_box()
        var text := "cargador fuera de pantalla"
        if not sbox.is_empty():
            var box: Rect2 = sbox["box"]
            var viewport := get_viewport().get_visible_rect().size
            var margin := minf(minf(box.position.x, viewport.x - box.end.x), minf(box.position.y, viewport.y - box.end.y))
            biggest = maxf(biggest, box.size.x)
            if margin > 6.0:
                visible_samples += 1
            var centroid: Vector2 = sbox["centro"]
            centroid.x = clampf(centroid.x, 0.0, viewport.x)
            centroid.y = clampf(centroid.y, 0.0, viewport.y)
            text = "cargador caja=(%.0f,%.0f %.0fx%.0f) centro=(%.0f,%.0f) margen=%.0fpx" % [
                box.position.x, box.position.y, box.size.x, box.size.y, centroid.x, centroid.y, margin]
        print("RELOAD %02d t=%.2fs mag=%d cham=%d slide=%.1fmm pose=%.2f %s" % [
            i, w.reload_elapsed, w.mag, w.chamber, w.slide_pos * 1000.0, w.reload_pose_blend, text])
    Engine.time_scale = 1.0
    print("RELOADCAPTURE frames=", frames, " muestras_con_cargador_visible=", visible_samples,
        " ancho_max=", snappedf(biggest, 1.0), "px dir=", dir)

## Vuelca a WAV lo que sale por Master durante una secuencia guionizada
## (disparos, recarga, pasos). Sirve para revisar el mix con el oído y para
## medirlo (pico, clipping) sin depender de la placa de sonido de la máquina.
## Uso: godot4 --path . --rendering-driver vulkan -- --audiocapture
func run_audiocapture() -> void:
    var capture := AudioEffectCapture.new()
    capture.buffer_length = 12.0
    AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), capture)
    await get_tree().create_timer(1.0).timeout
    capture.clear_buffer()
    for i in range(6):
        var before: int = _player.weapon.chamber
        _player.weapon.force_fire_once()
        print("AUDIOCAP shot ", i, " chamber ", before, "->", _player.weapon.chamber,
            " mag=", _player.weapon.mag, " slide=", snappedf(_player.weapon.slide_pos, 0.0001))
        await get_tree().create_timer(0.22).timeout
    _force_reloadable_state()
    _player.weapon.start_reload()
    await get_tree().create_timer(2.6).timeout
    for _i in range(4):
        GameAudio.play_2d("footstep", 0.0, randf_range(0.92, 1.08))
        await get_tree().create_timer(0.5).timeout
    # Comprobación de routing: cada voz debe sonar por el bus que dice el diseño.
    print("AUDIOCAPTURE estado arma mag=", _player.weapon.mag, " chamber=", _player.weapon.chamber,
        " slide=", snappedf(_player.weapon.slide_pos, 0.0001), " reloading=", _player.weapon.reloading)
    _player.weapon.force_fire_once()
    GameAudio.play_2d("footstep")
    GameAudio.play_3d("impact_concrete", _player.global_position + Vector3(0, 0, -2))
    await get_tree().create_timer(0.1).timeout
    var routed := {}
    for child in GameAudio.get_children():
        if child is AudioStreamPlayer and child.playing:
            routed[child.stream.resource_path.get_file()] = child.bus
    for child in get_tree().current_scene.get_children():
        if child is AudioStreamPlayer3D and child.playing:
            routed[child.stream.resource_path.get_file()] = child.bus
    for key in routed:
        print("AUDIOCAPTURE routing ", key, " -> ", routed[key])
    var buffer := capture.get_buffer(capture.get_frames_available())
    var path := ProjectSettings.globalize_path("res://captures/mix.wav")
    _save_wav(buffer, path)
    print("AUDIOCAPTURE frames=", buffer.size(), " path=", path)
    get_tree().quit()


func _save_wav(buffer: PackedVector2Array, path: String) -> void:
    var data := PackedByteArray()
    data.resize(buffer.size() * 4)
    var offset := 0
    for i in range(buffer.size()):
        data.encode_s16(offset, int(clampf(buffer[i].x, -1.0, 1.0) * 32767.0))
        data.encode_s16(offset + 2, int(clampf(buffer[i].y, -1.0, 1.0) * 32767.0))
        offset += 4
    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.stereo = true
    wav.mix_rate = int(AudioServer.get_mix_rate())
    wav.data = data
    wav.save_to_wav(path)
