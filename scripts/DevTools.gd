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
    {"id": "stage_omnis_baked", "label": "luces_omni_fuera_del_pase_dinamico"},
    {"id": "dir_shadow_off", "label": "sombra_direccional_off"},
    {"id": "vm_lights_off", "label": "luces_viewmodel_off"},
    {"id": "viewmodel_off", "label": "viewmodel_oculto"},
    {"id": "fx_off", "label": "impact_fx_off"},
    # Instrumentos para aislar el coste del viewmodel. NO son alternativas de
    # produccion: existen solo para saber que parte de sus milisegundos es
    # shader, que parte geometria y que parte script.
    {"id": "vm_std_mat", "label": "viewmodel_material_plano"},
    {"id": "vm_gun_off", "label": "solo_brazos"},
    {"id": "vm_arms_off", "label": "solo_arma"},
    {"id": "vm_meshes_off", "label": "ambas_mallas_off"},
    {"id": "vm_static", "label": "viewmodel_sin_script"},
]
const BENCH_DEFAULT_REPEATS := 2
const BENCH_DEFAULT_WARMUP := 1.0
const BENCH_DEFAULT_DURATION := 6.0

var _bench_stage_omnis: Array[OmniLight3D] = []
var _bench_viewmodel_lights: Array[OmniLight3D] = []
var _bench_sun: DirectionalLight3D
var _bench_vm_orig_mats := {}
var _bench_vm_flat_mats := {}
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
    _bench_bind_viewmodel_materials()


## Prepara una version plana (StandardMaterial3D) de los materiales del
## viewmodel, con el mismo color/metal/rugosidad base. Comparar `base` contra
## `vm_std_mat` dice cuanto del coste del viewmodel es material y cuanto la
## geometria que hay debajo. Es un instrumento de medida, no una alternativa.
func _bench_bind_viewmodel_materials() -> void:
    _bench_vm_orig_mats.clear()
    _bench_vm_flat_mats.clear()
    var w = _player.weapon
    if w == null:
        return
    for mesh_node in _viewmodel_meshes(w):
        var mi := mesh_node as MeshInstance3D
        if mi == null or mi.mesh == null:
            continue
        var orig: Array = []
        var flat: Array = []
        for i in range(mi.mesh.get_surface_count()):
            var m: Material = mi.get_surface_override_material(i)
            if m == null:
                m = mi.mesh.surface_get_material(i)
            orig.append(m)
            var std := StandardMaterial3D.new()
            if m is ShaderMaterial:
                std.albedo_color = m.get_shader_parameter("base_color")
                std.metallic = float(m.get_shader_parameter("metallic"))
                std.roughness = float(m.get_shader_parameter("roughness"))
            elif m is StandardMaterial3D:
                std.albedo_color = (m as StandardMaterial3D).albedo_color
                std.metallic = (m as StandardMaterial3D).metallic
                std.roughness = (m as StandardMaterial3D).roughness
            flat.append(std)
        _bench_vm_orig_mats[mi] = orig
        _bench_vm_flat_mats[mi] = flat


## Mallas visibles del viewmodel: cuerpo OWK + cargador + brazos.
func _viewmodel_meshes(w) -> Array:
    var out: Array = []
    var stack: Array = []
    if w.pistol_holder != null:
        stack.append(w.pistol_holder)
    if w.arms_mount != null:
        stack.append(w.arms_mount)
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
            out.append(n)
        for c in n.get_children():
            stack.append(c)
    return out


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
    var stage_on := variant_id != "stage_omnis_off" and variant_id != "stage_omnis_baked"
    for light in _bench_stage_omnis:
        light.visible = stage_on
        # `stage_omnis_off` oculta las luces y `stage_omnis_baked` las saca del
        # pase dinamico (BAKE_STATIC). Medido, las dos ahorran lo mismo
        # (13.2 ms contra 12.8 ms), asi que ocultarlas YA mide bien su coste y
        # la segunda solo sirve para confirmarlo por una via independiente.
        light.light_bake_mode = (Light3D.BAKE_STATIC if variant_id == "stage_omnis_baked"
            else Light3D.BAKE_DISABLED)
    if _bench_sun != null:
        _bench_sun.shadow_enabled = variant_id != "dir_shadow_off"
    var vm_lights_on := variant_id != "vm_lights_off"
    for light in _bench_viewmodel_lights:
        light.visible = vm_lights_on
    _player.weapon.visible = variant_id != "viewmodel_off"
    # Instrumentos de aislamiento del viewmodel.
    var w = _player.weapon
    var flat := variant_id == "vm_std_mat"
    for mesh_node in _bench_vm_orig_mats:
        var src: Array = _bench_vm_flat_mats[mesh_node] if flat else _bench_vm_orig_mats[mesh_node]
        for i in range(src.size()):
            mesh_node.set_surface_override_material(i, src[i])
    if w.pistol_holder != null:
        w.pistol_holder.visible = variant_id != "vm_gun_off" and variant_id != "vm_meshes_off"
    if w.arms_mesh_visible != null:
        w.arms_mesh_visible.visible = variant_id != "vm_arms_off" and variant_id != "vm_meshes_off"
    w.set_process(variant_id != "vm_static")


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
    if w.arms_player != null:
        var arms_anim := "FPS_Pistol_Idle"
        if anim_name == "Shoot":
            arms_anim = "FPS_Pistol_Fire"
        elif anim_name == "Reload":
            arms_anim = "FPS_Pistol_Reload_easy"
        if w._play_arms_anim(arms_anim, true):
            w.arms_player.seek(t, true)


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
    if w.sight_marker != null and w.muzzle != null:
        var camv: Camera3D = _player.camera
        var pm: Vector2 = camv.unproject_position((w.sight_marker as Node3D).global_position)
        var pb: Vector2 = camv.unproject_position((w.muzzle as Node3D).global_position)
        print("VISUAL_MIRA ", state, " mira_px=(", snappedf(pm.x, 1.0), ",", snappedf(pm.y, 1.0),
            ") boca_px=(", snappedf(pb.x, 1.0), ",", snappedf(pb.y, 1.0), ")")


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


## Huesos que deciden el encuadre de los brazos: hombro, codo, mano y punta de
## cada dedo. `Rif` es el arma, y sirve de referencia de "donde deberia estar la
## mano izquierda si el agarre fuera a dos manos".
const ARM_BONES := [
    "Arm_L", "UpArm_L", "Forearm_L", "Hand_L",
    "Bone_L.007", "Bone_L.011", "Bone_L.015", "Bone_L.019", "Bone_L.022",
    "Arm_R", "UpArm_R", "Forearm_R", "Hand_R",
    "Bone_R.007", "Bone_R.011", "Bone_R.015", "Bone_R.019", "Bone_R.022",
    "Rif",
]


## Orientacion real del arma leida de los HUESOS del rig (no de los marcadores,
## que en el paquete coherente caen lejos de la pistola visible). `Rif` es el
## hueso del arma y `Pmag` el del cargador: el cargador entra hacia ARRIBA en la
## empuñadura, asi que su eje es la vertical del arma, y la boca es
## perpendicular a esa vertical. Los tres ejes se dan en espacio de CAMARA
## (x=derecha, y=arriba, z=hacia atras), que es donde "apunta arriba o abajo"
## tiene sentido.
func _print_bone_axes(label: String) -> void:
    var w = _player.weapon
    var sk: Skeleton3D = w.arms_skeleton
    if sk == null:
        return
    var cam: Camera3D = _player.camera
    var inv_cam := cam.global_transform.basis.inverse()
    for bone_name in ["Rif", "Pmag"]:
        var idx := -1
        for b in range(sk.get_bone_count()):
            if sk.get_bone_name(b).begins_with(bone_name):
                idx = b
                break
        if idx < 0:
            continue
        var world_b: Basis = sk.global_transform.basis * sk.get_bone_global_pose(idx).basis
        var cb: Basis = inv_cam * world_b
        print("BONE_AXES ", label, " ", bone_name,
            " x=", cb.x.snapped(Vector3(0.001, 0.001, 0.001)),
            " y=", cb.y.snapped(Vector3(0.001, 0.001, 0.001)),
            " z=", cb.z.snapped(Vector3(0.001, 0.001, 0.001)))


## Vértices de una malla ESQUELETIZADA en la pose viva, en el espacio del nodo
## indicado. Para una malla con piel, `mesh.surface_get_arrays()[VERTEX]` está en
## el espacio de BIND: transformarlos por la cadena del nodo da la pose de
## reposo, no la que se ve. La deformación real es
##   p = suma_i  w_i * (pose_i * rest_i^-1) * v
## y es la única forma de saber dónde está de verdad la pistola que el autor
## esculpió dentro del rig de los brazos.
func _skinned_verts(mi: MeshInstance3D, sk: Skeleton3D, space: Node3D) -> PackedVector3Array:
    var out := PackedVector3Array()
    var inv_rest: Array = []
    for b in range(sk.get_bone_count()):
        inv_rest.append(sk.get_bone_global_rest(b).affine_inverse())
    for si in range(mi.mesh.get_surface_count()):
        var arrays := mi.mesh.surface_get_arrays(si)
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        for i in range(verts.size()):
            var v: Vector3 = verts[i]
            if bones.size() < (i + 1) * 4:
                out.append(v)
                continue
            var acc := Vector3.ZERO
            var total := 0.0
            for k in range(4):
                var w := weights[i * 4 + k]
                if w <= 0.0:
                    continue
                var b := bones[i * 4 + k]
                acc += w * ((sk.get_bone_global_pose(b) * inv_rest[b]) * v)
                total += w
            if total > 0.0:
                out.append(acc / total)
            else:
                out.append(v)
    return out


## Diagnóstico de la mira: dónde está de verdad la pistola del autor dentro del
## rig de brazos, en qué ejes, y dónde cree el juego que está la mira. Sin esto
## el ADS se corrige a ciegas.
func run_sightdiag() -> void:
    await get_tree().create_timer(0.8).timeout
    var w = _player.weapon
    var sk: Skeleton3D = w.arms_skeleton
    if sk == null or w.arms_root == null:
        print("SIGHTDIAG sin brazos")
        get_tree().quit()
        return
    var mallas: Array = []
    var stack: Array = [w.arms_root]
    var mayor := -1
    var brazos: MeshInstance3D = null
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
            mallas.append(n)
            var vc := 0
            for si in range((n as MeshInstance3D).mesh.get_surface_count()):
                vc += ((n as MeshInstance3D).mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
            if vc > mayor:
                mayor = vc
                brazos = n
        for c in n.get_children():
            stack.append(c)
    for m in mallas:
        var mi := m as MeshInstance3D
        var vv := _skinned_verts(mi, sk, w.arms_root)
        var tris := 0
        for si in range(mi.mesh.get_surface_count()):
            var idx: PackedInt32Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX]
            tris += idx.size() / 3 if idx.size() > 0 else (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
        var bb := _bounds_of(vv)
        print("SIGHTDIAG malla=", mi.name, " verts=", vv.size(), " tris=", tris,
            " caja=", bb.size.snapped(Vector3(0.001, 0.001, 0.001)),
            " es_brazos=", mi == brazos)
    var pv := PackedVector3Array()
    for m in mallas:
        if m == brazos:
            continue
        pv.append_array(_skinned_verts(m as MeshInstance3D, sk, w.arms_root))
    if pv.is_empty():
        print("SIGHTDIAG sin malla de pistola")
        get_tree().quit()
        return
    # Proyeccion a pantalla de los vertices de la pistola: si esto no coincide
    # con la pistola que se ve en la captura, el fallo esta en el skinning.
    var camv: Camera3D = _player.camera
    var smin := Vector2(INF, INF)
    var smax := Vector2(-INF, -INF)
    var dentro := 0
    for v in pv:
        var wv: Vector3 = sk.global_transform * v
        if camv.is_position_behind(wv):
            continue
        var sp := camv.unproject_position(wv)
        smin = smin.min(sp)
        smax = smax.max(sp)
        dentro += 1
    print("SIGHTDIAG pistola_px min=(", snappedf(smin.x, 1.0), ",", snappedf(smin.y, 1.0),
        ") max=(", snappedf(smax.x, 1.0), ",", snappedf(smax.y, 1.0), ") visibles=", dentro, "/", pv.size())
    var marc: Vector3 = (w.sight_marker as Node3D).global_position
    var mp := camv.unproject_position(marc)
    print("SIGHTDIAG marcador_px=(", snappedf(mp.x, 1.0), ",", snappedf(mp.y, 1.0), ") mire_en_caja=",
        marc.x > -1e9, " dist_marcador_pistola=", snappedf(marc.distance_to(_bounds_of(pv).get_center() + (sk.global_transform.origin - sk.global_transform.origin)), 0.001))
    var caja := _bounds_of(pv)
    print("SIGHTDIAG caja_viva_esqueleto=", caja.position.snapped(Vector3(0.001, 0.001, 0.001)),
        " tam=", caja.size.snapped(Vector3(0.001, 0.001, 0.001)), " verts=", pv.size())
    var rif := -1
    var pmag := -1
    for b in range(sk.get_bone_count()):
        var bn := sk.get_bone_name(b)
        if bn.begins_with("Rif"):
            rif = b
        elif bn.begins_with("Pmag"):
            pmag = b
    if rif >= 0:
        print("SIGHTDIAG Rif_rest origin=", sk.get_bone_global_rest(rif).origin.snapped(Vector3(0.001, 0.001, 0.001)),
            " x=", sk.get_bone_global_rest(rif).basis.x.snapped(Vector3(0.001, 0.001, 0.001)),
            " y=", sk.get_bone_global_rest(rif).basis.y.snapped(Vector3(0.001, 0.001, 0.001)),
            " z=", sk.get_bone_global_rest(rif).basis.z.snapped(Vector3(0.001, 0.001, 0.001)))
        print("SIGHTDIAG Rif_pose origin=", sk.get_bone_global_pose(rif).origin.snapped(Vector3(0.001, 0.001, 0.001)),
            " z=", sk.get_bone_global_pose(rif).basis.z.snapped(Vector3(0.001, 0.001, 0.001)))
        # Vértices de la pistola en el frame del hueso del arma: ahí los ejes sí
        # tienen significado conocido (ver el informe del barrido de ángulos).
        var inv_pose := sk.get_bone_global_pose(rif).affine_inverse()
        var en_hueso := PackedVector3Array()
        for v in pv:
            en_hueso.append(inv_pose * v)
        var ch := _bounds_of(en_hueso)
        print("SIGHTDIAG caja_en_hueso pos=", ch.position.snapped(Vector3(0.001, 0.001, 0.001)),
            " tam=", ch.size.snapped(Vector3(0.001, 0.001, 0.001)))
    if pmag >= 0 and rif >= 0:
        var pm: Vector3 = sk.get_bone_global_pose(rif).affine_inverse() * sk.get_bone_global_pose(pmag).origin
        print("SIGHTDIAG Pmag_en_Rif=", pm.snapped(Vector3(0.001, 0.001, 0.001)))
    if w.sight_marker != null and w.pistol_holder != null:
        var a: Transform3D = sk.global_transform.affine_inverse() * (w.pistol_holder as Node3D).global_transform
        var m: Vector3 = a * (w.sight_marker as Node3D).position
        print("SIGHTDIAG sight_marker_en_esqueleto=", m.snapped(Vector3(0.001, 0.001, 0.001)),
            " dentro_de_caja=", caja.has_point(m))
    print("SIGHTDIAG_DONE")
    get_tree().quit()


## Tabla de encuadre de los huesos de los brazos: por cada hueso, donde cae en
## pantalla y con cuanto margen. Un margen negativo significa que el hueso queda
## FUERA del viewport; "detras" significa que esta por detras del plano de la
## camara. Esto es lo que decide si los hombros salen o no, sin discutirlo.
func run_armdiag() -> void:
    await get_tree().create_timer(0.8).timeout
    _player.weapon.set_aim(false)
    await _settle_pose()
    _print_arm_frame("hip")
    _player.weapon.set_aim(true)
    await _settle_pose()
    _print_arm_frame("ads")
    _player.weapon.set_aim(false)
    await _settle_pose()
    _print_arm_screen_box("hip")
    print("ARM_DIAG_DONE")
    get_tree().quit()


func _print_arm_frame(label: String) -> void:
    var w = _player.weapon
    var sk: Skeleton3D = w.arms_skeleton
    var cam: Camera3D = _player.camera
    if sk == null:
        print("ARM ", label, " sin esqueleto de brazos")
        return
    var vp := get_viewport().get_visible_rect().size
    var cam_t: Transform3D = cam.global_transform
    print("ARM_FRAME ", label, " viewport=", vp)
    for prefix in ARM_BONES:
        var idx := -1
        for b in range(sk.get_bone_count()):
            if sk.get_bone_name(b).begins_with(prefix):
                idx = b
                break
        if idx < 0:
            continue
        var world: Vector3 = sk.global_transform * sk.get_bone_global_pose(idx).origin
        # Distancia a lo largo del eje de vision: negativa = delante de la camara.
        var depth: float = (world - cam_t.origin).dot(-cam_t.basis.z)
        var side: float = (world - cam_t.origin).dot(cam_t.basis.x)
        var up: float = (world - cam_t.origin).dot(cam_t.basis.y)
        var screen := cam.unproject_position(world)
        var margin := minf(minf(screen.x, vp.x - screen.x), minf(screen.y, vp.y - screen.y))
        print("ARM ", label, " ", prefix, " #", idx, " depth=", snappedf(depth, 0.001),
            " side=", snappedf(side, 0.001), " up=", snappedf(up, 0.001),
            " px=(", snappedf(screen.x, 1.0), ",", snappedf(screen.y, 1.0), ")",
            " margen=", snappedf(margin, 1.0),
            " ", ("DETRAS" if depth <= 0.0 else ("DENTRO" if margin > 0.0 else "FUERA")))
    _print_bore(label)
    _print_bone_axes(label)


## Direccion real de la boca del arma respecto al eje de vision, y donde cae el
## extremo de cada punta en pantalla. Es lo que decide si el arma "apunta hacia
## arriba" o hacia abajo: la perspectiva sola enganya, porque el extremo lejano
## sube hacia el horizonte aunque el arma este inclinada hacia el suelo.
func _print_bore(label: String) -> void:
    var w = _player.weapon
    if w.muzzle == null or w.sight_marker == null:
        return
    var cam: Camera3D = _player.camera
    var world_muzzle: Vector3 = (w.muzzle as Node3D).global_transform.origin
    var world_sight: Vector3 = (w.sight_marker as Node3D).global_transform.origin
    var dir := (world_muzzle - world_sight)
    if dir.length() < 0.0001:
        return
    dir = dir.normalized()
    var en_cam: Vector3 = cam.global_transform.basis.inverse() * dir
    var elevacion := rad_to_deg(asin(clampf(en_cam.y, -1.0, 1.0)))
    var y_mira := cam.unproject_position(world_sight).y
    var y_boca := cam.unproject_position(world_muzzle).y
    print("BORE ", label, " elevacion=", snappedf(elevacion, 0.1), " grados (positivo=arriba)",
        " profundidad_boca=", snappedf((world_muzzle - cam.global_transform.origin).dot(-cam.global_transform.basis.z), 0.001),
        " px_y_mira=", snappedf(y_mira, 1.0), " px_y_boca=", snappedf(y_boca, 1.0),
        " ", ("BOCA_ARRIBA" if y_boca < y_mira else "BOCA_ABAJO"))


## Caja en pantalla de cada malla de los brazos: dice si la masa grande (hombro)
## asoma por algun borde, que es lo que se ve como "sale el hombro".
func _print_arm_screen_box(label: String) -> void:
    var w = _player.weapon
    if w.arms_root == null:
        return
    var cam: Camera3D = _player.camera
    var stack: Array = [w.arms_root]
    var vp := get_viewport().get_visible_rect().size
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
            var mi := n as MeshInstance3D
            var box := _screen_bbox(_bind_aabb(mi), mi.global_transform, cam)
            var smin: Vector2 = box["min"]
            var smax: Vector2 = box["max"]
            var dentro := smax.x > 0.0 and smax.y > 0.0 and smin.x < vp.x and smin.y < vp.y
            print("ARM_BOX ", label, " ", mi.name, " px_min=(", snappedf(smin.x, 1.0), ",", snappedf(smin.y, 1.0),
                ") px_max=(", snappedf(smax.x, 1.0), ",", snappedf(smax.y, 1.0), ")",
                " ", ("TOCA_ENCUADRE" if dentro else "FUERA_ENCUADRE"))
        for c in n.get_children():
            stack.append(c)


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
    var bbox := _screen_bbox(w.gun_box, (w.pistol_holder as Node3D).global_transform, cam)
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


## Posición viva de las piezas del arma (pose actual) en espacio de recoil.
func _print_live_bones(label: String) -> void:
    var w = _player.weapon
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    for part_name in ["Slide", "Magazine", "Trigger", "Barrel"]:
        if not w.pistol_parts.has(part_name):
            continue
        var live: Vector3 = recoil_inv * ((w.pistol_parts[part_name] as Node3D).global_position)
        print("LIVE ", label, " ", part_name, " pose=", live.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " slide_pos=", snappedf(w.slide_pos, 0.0001))


## Comprueba que la corredera viaja hacia atrás (+Z) en el marco del arma.
func _print_bone_travel() -> Dictionary:
    var w = _player.weapon
    var holder_inv: Transform3D = (w.pistol_holder as Node3D).global_transform.affine_inverse()
    var slide := w.pistol_parts["Slide"] as Node3D
    var rest: Vector3 = holder_inv * slide.global_position
    w.slide_pos = w.SLIDE_TRAVEL
    w._apply_pistol_parts()
    var posed: Vector3 = holder_inv * slide.global_position
    w.slide_pos = 0.0
    w._apply_pistol_parts()
    var deltas := {"Slide": posed - rest}
    print("TRAVEL Slide rest=", rest.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " posed=", posed.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " delta=", (posed - rest).snapped(Vector3(0.0001, 0.0001, 0.0001)))
    return deltas


## Recorrido del cargador durante una recarga real, medido en vivo sobre su
## malla: lo arrastra el hueso Pmag del autor, asi que se muestrea mientras
## ocurre. El recorrido es el diametro de la nube de posiciones (sin referencia
## de reposo: el hueso manda).
func _measure_reload_mag() -> Dictionary:
    var w = _player.weapon
    if w.pistol_mag_node == null:
        return {}
    var samples: Array[Vector3] = []
    var on_screen := 0
    var best_margin := -1e9
    var viewport := get_viewport().get_visible_rect().size
    var cam: Camera3D = _player.camera
    for _i in range(26):
        await get_tree().create_timer(0.1).timeout
        var world: Vector3 = (w.pistol_mag_node as Node3D).global_position
        samples.append(world)
        # Lo que importa de verdad: que el cargador se VEA salir y entrar.
        if not cam.is_position_behind(world):
            var screen := cam.unproject_position(world)
            var margin := minf(minf(screen.x, viewport.x - screen.x), minf(screen.y, viewport.y - screen.y))
            best_margin = maxf(best_margin, margin)
            if margin > 20.0:
                on_screen += 1
    var max_travel := 0.0
    for a in samples:
        for b in samples:
            max_travel = maxf(max_travel, a.distance_to(b))
    print("RELOAD_MAG recorrido_max=", snappedf(max_travel, 0.001),
        " m muestras_en_pantalla=", on_screen, "/26 margen_max=", snappedf(best_margin, 0.1), "px")
    return {"travel": max_travel, "on_screen": on_screen}


func _print_geometry(label: String) -> void:
    var cam: Camera3D = _player.camera
    var w = _player.weapon
    if w.pistol_holder == null:
        print("GEOMETRY ", label, " sin arma")
        return
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    # La geometria visible es la OWK bajo PBody: su caja en marco del arma
    # proyectada por el global del cuerpo.
    var bbox := _screen_bbox(w.gun_box, (w.pistol_holder as Node3D).global_transform, cam)
    var sight_screen: Vector2 = cam.unproject_position(w.get_sight_world_position())
    var muzzle_screen: Vector2 = cam.unproject_position(w.muzzle.global_position)
    var sight_cam: Vector3 = cam.global_transform.affine_inverse() * w.get_sight_world_position()
    var muzzle_cam: Vector3 = cam.global_transform.affine_inverse() * w.muzzle.global_position
    var pm: Vector3 = recoil_inv * (w.muzzle as Node3D).global_position
    var pe: Vector3 = recoil_inv * (w.ejection_port as Node3D).global_position
    var ps: Vector3 = recoil_inv * w.get_sight_world_position()
    print("MOUNT ", label, " escala_brazos=", snappedf(w.arms_scale, 0.0001),
        " ads_offset=", w.ads_offset.snapped(Vector3(0.001, 0.001, 0.001)),
        " ads_rot_deg=", (w.ads_rot * 180.0 / PI).snapped(Vector3(0.1, 0.1, 0.1)))
    print("GUNBOX ", label,
        " min=", w.gun_box.position.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " size=", w.gun_box.size.snapped(Vector3(0.0001, 0.0001, 0.0001)))
    if w.arms_skeleton != null:
        var sk: Skeleton3D = w.arms_skeleton
        for bone_prefix in ["PBody", "Pmag", "Rif_", "Hand_R", "Hand_L"]:
            for bi in range(sk.get_bone_count()):
                if sk.get_bone_name(bi).begins_with(bone_prefix):
                    var gp: Transform3D = sk.global_transform * sk.get_bone_global_rest(bi)
                    var rel: Vector3 = recoil_inv * gp.origin
                    print("BONE ", label, " ", sk.get_bone_name(bi), " rel=", rel.snapped(Vector3(0.0001, 0.0001, 0.0001)))
                    break
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
    if not w.pistol_ok:
        failures.append("la OWK no quedo utilizable")
    var size: Vector3 = w.gun_box.size
    if absf(size.x - 0.034) > 0.005 or absf(size.y - 0.13) > 0.006 or absf(size.z - 0.186) > 0.004:
        failures.append("caja del arma %s (esperado ~0.034 x 0.13 x 0.186)" % size)
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
    print("GEOMETRYDEBUG passed=", passed, " caja=", size.snapped(Vector3(0.0001, 0.0001, 0.0001)),
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





## Caja del cargador en pantalla, medida sobre su GEOMETRIA viva: el cargador
## cuelga del hueso Pmag, asi que su caja mundial ya esta donde se ve.
func _mag_screen_box() -> Dictionary:
    var w = _player.weapon
    if w.pistol_mag_node == null:
        return {}
    var posed := AABB()
    var first := true
    var stack: Array = [w.pistol_mag_node]
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
            var mi := n as MeshInstance3D
            var local := _bind_aabb(mi)
            var world := _transform_aabb(local, mi.global_transform)
            if first:
                posed = world
                first = false
            else:
                posed = posed.merge(world)
        for c in n.get_children():
            stack.append(c)
    if first:
        return {}
    var cam: Camera3D = _player.camera
    var sbox := Rect2()
    var started := false
    var cmin := posed.position
    var cmax := posed.position + posed.size
    for xi in [0.0, 1.0]:
        for yi in [0.0, 1.0]:
            for zi in [0.0, 1.0]:
                var corner := Vector3(lerpf(cmin.x, cmax.x, xi), lerpf(cmin.y, cmax.y, yi), lerpf(cmin.z, cmax.z, zi))
                if cam.is_position_behind(corner):
                    return {}
                var sp := cam.unproject_position(corner)
                if not started:
                    sbox = Rect2(sp, Vector2.ZERO)
                    started = true
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
