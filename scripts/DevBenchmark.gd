extends Node

## Banco de rendimiento A/B: apaga o enciende un subsistema cada vez sobre la
## misma escena, camara, resolucion, calentamiento y duracion. No es un profiler
## generico. Uso: `--fpsbench [--fpsvariant=...] [--fpsreps=N]`.

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
    {"id": "vm_gun_off", "label": "pistola_off"},
    {"id": "vm_arms_off", "label": "brazos_off"},
    {"id": "vm_meshes_off", "label": "piel_off_esqueleto_animado"},
    {"id": "vm_static", "label": "viewmodel_sin_script"},
    # Congela el AnimationPlayer del viewmodel en su pose actual: separa el
    # coste de evaluar 928 huesos × ~400 pistas del coste de dibujar la piel.
    {"id": "vm_anim_off", "label": "viewmodel_animacion_pausada"},
]

const BENCH_DEFAULT_REPEATS := 2

const BENCH_DEFAULT_WARMUP := 1.0

const BENCH_DEFAULT_DURATION := 6.0

var _player: CharacterBody3D
var _hud: CanvasLayer
var _main: Node3D
var common: DevCommon

var _bench_stage_omnis: Array[OmniLight3D] = []
var _bench_viewmodel_lights: Array[OmniLight3D] = []
var _bench_sun: DirectionalLight3D
var _bench_vm_orig_mats := {}
var _bench_vm_flat_mats := {}
var _bench_stress := false
var _bench_stress_accum := 0.0
var _bench_stress_spawned := 0


func setup(main_node: Node3D, player_node: CharacterBody3D, hud_node: CanvasLayer, common_node) -> void:
    _player = player_node
    _hud = hud_node
    _main = main_node


func run_fpsbench() -> void:
    # Sin vsync: en headless el viewport es diminuto y con vsync la medida se
    # queda clavada en la frecuencia del monitor. La ventana real manda.
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    common.lock_viewport()
    _bench_bind_nodes()
    _bench_stress = OS.get_cmdline_user_args().has("--fpsstress")
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
)

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
            if not runs.has(id):
                runs[id] = []
            runs[id].append(stats)
            _bench_print_run(repeat + 1, repeats, entry, stats)

    _bench_stress = false
    ImpactFX.spawning_enabled = true
    _bench_apply_variant("base")
    _bench_print_summary(variants, runs)
    get_tree().quit()


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
    if _player.weapon != null and _player.weapon.viewmodel.pose_root != null:
        for child in _player.weapon.viewmodel.pose_root.get_children():
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
    for mesh_node in common.viewmodel_meshes(w):
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
    # Familias de mallas del asset unico: pistola + manos + mangas.
    var gun_meshes := common.gun_family_meshes(w, ["Object_938", "Object_939", "Object_940"])
    var arm_meshes := common.gun_family_meshes(w, ["Object_8", "Object_7"])
    for m in gun_meshes:
        (m as MeshInstance3D).visible = variant_id != "vm_gun_off" and variant_id != "vm_meshes_off"
    for m in arm_meshes:
        (m as MeshInstance3D).visible = variant_id != "vm_arms_off" and variant_id != "vm_meshes_off"
    # vm_meshes_off apaga las 5 mallas pero deja esqueleto+animacion: separa
    # render de skinning/animacion. vm_anim_off (ver abajo) aisla la animacion.
    w.set_process(variant_id != "vm_static")
    # Pausar la animación deja la última pose en pantalla: el delta contra base
    # es el coste de evaluar el esqueleto cada frame, sin tocar ni meshes ni
    # luces ni script de mecánica.
    if w.viewmodel.arms_player != null:
        w.viewmodel.arms_player.stream_paused = variant_id == "vm_anim_off"


## Guarda una captura del estado exacto de la variante, a la misma resolución
## y cámara que el benchmark, para poder revisar que la optimización no cambió
## la imagen más de lo aceptable.
##
## La escena se congela antes de capturar: sin eso las capturas del benchmark NO
## son comparables entre sí. Medido con el banco anterior: base contra fx_off
## (que cuesta 0.08 ms y no cambia nada visible) daba 6.3/255 de diferencia
## media y 36.6% de píxeles por encima de 4/255, todo ello balanceo del arma y
## respiración de la cámara entre una variante y la siguiente.
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
