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
    if OS.get_cmdline_user_args().has("--aimtest"):
        _run_aimtest()
    if OS.get_cmdline_user_args().has("--pentest"):
        _run_pentest()
    if OS.get_cmdline_user_args().has("--reloadtest"):
        _run_reloadtest()
    if OS.get_cmdline_user_args().has("--fpsbench"):
        _run_fpsbench()
    if OS.get_cmdline_user_args().has("--probe"):
        _run_probe()
    if OS.get_cmdline_user_args().has("--geometrydebug"):
        _run_geometrydebug()
    if OS.get_cmdline_user_args().has("--timeline"):
        _run_timeline()
    if OS.get_cmdline_user_args().has("--audiocapture"):
        _run_audiocapture()


## Vuelca a WAV lo que sale por Master durante una secuencia guionizada
## (disparos, recarga, pasos). Sirve para revisar el mix con el oído y para
## medirlo (pico, clipping) sin depender de la placa de sonido de la máquina.
## Uso: godot4 --path . --rendering-driver vulkan -- --audiocapture
func _run_audiocapture() -> void:
    var capture := AudioEffectCapture.new()
    capture.buffer_length = 12.0
    AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), capture)
    await get_tree().create_timer(1.0).timeout
    capture.clear_buffer()
    for i in range(6):
        var before: int = player.weapon.chamber
        player.weapon.force_fire_once()
        print("AUDIOCAP shot ", i, " chamber ", before, "->", player.weapon.chamber,
            " mag=", player.weapon.mag, " slide=", snappedf(player.weapon.slide_pos, 0.0001))
        await get_tree().create_timer(0.22).timeout
    _force_reloadable_state()
    player.weapon.start_reload()
    await get_tree().create_timer(2.6).timeout
    for _i in range(4):
        GameAudio.play_2d("footstep", 0.0, randf_range(0.92, 1.08))
        await get_tree().create_timer(0.5).timeout
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


## Timeline de capturas: graba una secuencia guionizada (quieto, caminando,
## apuntar, disparos y recarga) guardando un frame cada 0.1 s con sus métricas,
## para revisar el arma con los ojos en vez de suponer.
## Uso: godot4 --path . --rendering-driver vulkan -- --timeline
func _run_timeline() -> void:
    var dir := ProjectSettings.globalize_path("res://captures/timeline")
    DirAccess.make_dir_recursive_absolute(dir)
    print("TIMELINE dir=", dir)
    await get_tree().create_timer(1.0).timeout
    player.weapon.reserve = 34
    _timeline_fired = 0
    var step := 0.1
    var index := 0
    while index * step < 5.5:
        var t := index * step
        _timeline_drive(t)
        await get_tree().create_timer(step).timeout
        await _capture_view("%s/frame_%03d.png" % [dir, index])
        _print_timeline_metrics(index, t)
        index += 1
    print("TIMELINE_DONE frames=", index, " dir=", dir)
    get_tree().quit()


var _timeline_fired := 0


## Guion: hip quieto -> caminando -> ADS -> dos disparos -> recarga.
func _timeline_drive(t: float) -> void:
    var w = player.weapon
    if t < 1.0:
        player.current_speed = 0.0
        w.set_motion(0.0, Vector2.ZERO, Vector2.ZERO)
        w.set_aim(false)
    elif t < 2.0:
        player.current_speed = 4.0
        w.set_motion(4.0, Vector2(0.0, 1.0), Vector2.ZERO)
        w.set_aim(false)
    elif t < 4.2:
        player.current_speed = 0.0
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
    var cam: Camera3D = player.camera
    var w = player.weapon
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
        index, rad_to_deg(player.pitch), rad_to_deg(player.pitch_target), rad_to_deg(player.camera.rotation.z),
        player.recoil_pitch, rad_to_deg(player.yaw), player.global_position.y
    ])


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


func _run_fpsbench() -> void:
    # Sin vsync y con ventana real: en headless el viewport es diminuto y con
    # vsync la medida se queda clavada en la frecuencia del monitor.
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    await get_tree().create_timer(1.5).timeout
    var samples: Array[float] = []
    var elapsed := 0.0
    while elapsed < 8.0:
        await get_tree().process_frame
        var dt := get_process_delta_time()
        elapsed += dt
        samples.append(Engine.get_frames_per_second())
    var total := 0.0
    var minimum := 10000.0
    for fps in samples:
        total += fps
        minimum = minf(minimum, fps)
    print("FPSBENCH avg=", snapped(total / maxf(1.0, samples.size()), 0.1), " min=", snapped(minimum, 0.1), " samples=", samples.size(), " viewport=", get_viewport().get_visible_rect().size)
    get_tree().quit()


func _capture_view(path: String) -> void:
    await RenderingServer.frame_post_draw
    var image := get_viewport().get_texture().get_image()
    image.save_png(path)


func _probe_state(state_name: String) -> void:
    Engine.time_scale = 0.0
    hud.post.visible = false
    await get_tree().process_frame
    await get_tree().process_frame
    await _capture_view("/tmp/probe_%s_with.png" % state_name)
    player.weapon.visible = false
    await get_tree().process_frame
    await get_tree().process_frame
    await _capture_view("/tmp/probe_%s_without.png" % state_name)
    player.weapon.visible = true
    hud.post.visible = true
    Engine.time_scale = 1.0
    print("PROBE ", state_name, " listo")


func _run_probe() -> void:
    await get_tree().create_timer(0.8).timeout
    player.weapon.set_aim(false)
    await _probe_state("hip")
    player.weapon.set_aim(true)
    await get_tree().create_timer(0.6).timeout
    await _probe_state("ads")
    # Fogonazo: time_scale queda en 0, así que se congela en el frame del disparo.
    player.weapon.force_fire_once()
    await _probe_state("shot")
    player.weapon.set_aim(false)
    await get_tree().create_timer(0.2).timeout
    _force_reloadable_state()
    player.weapon.start_reload()
    await get_tree().create_timer(0.75).timeout
    await _probe_state("reload")
    print("PROBE_DONE")
    get_tree().quit()


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


func _run_geometrydebug() -> void:
    await get_tree().create_timer(0.8).timeout
    player.weapon.set_aim(false)
    await get_tree().create_timer(0.5).timeout
    _print_geometry("hip")
    player.weapon.set_aim(true)
    await get_tree().create_timer(0.8).timeout
    _print_geometry("ads")
    player.weapon.set_aim(false)
    await get_tree().create_timer(0.4).timeout
    _print_bone_travel()
    # Durante la recarga: dónde acaba el cargador medido en frame de arma.
    _force_reloadable_state()
    player.weapon.start_reload()
    await get_tree().create_timer(0.75).timeout
    _print_live_bones("reload")
    get_tree().quit()


## Deja el arma en un estado que sí admite recarga: con el cargador lleno
## start_reload() no hace nada y las capturas de "recarga" saldrían falsas.
func _force_reloadable_state() -> void:
    player.weapon.mag = 0
    player.weapon.chamber = 0
    player.weapon.reserve = 17


## Posición viva de los huesos (pose actual, no la de reposo) en frame de arma.
func _print_live_bones(label: String) -> void:
    var w = player.weapon
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    var skeleton_node: Skeleton3D = w.skeleton
    for bone_name in ["Slide", "Magazine", "Trigger", "Barrel"]:
        var idx: int = skeleton_node.find_bone(bone_name)
        if idx < 0:
            continue
        var live: Vector3 = recoil_inv * (skeleton_node.global_transform * skeleton_node.get_bone_global_pose(idx).origin)
        print("LIVE ", label, " ", bone_name, " pose=", live.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " drop=", snappedf(w.mag_visual_drop, 0.0001), " slide_pos=", snappedf(w.slide_pos, 0.0001))


## Comprueba que la corredera y el cargador viajan en la dirección medida: la
## corredera hacia atrás (+Z) y el cargador hacia abajo (-Y), en frame de arma.
func _print_bone_travel() -> void:
    var w = player.weapon
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    w.slide_pos = 0.039
    w.mag_visual_drop = 0.20
    w._apply_bone_poses()
    for bone_name in ["Slide", "Magazine"]:
        var idx: int = (w.skeleton as Skeleton3D).find_bone(bone_name)
        if idx < 0:
            continue
        var posed: Vector3 = recoil_inv * ((w.skeleton as Skeleton3D).global_transform * (w.skeleton as Skeleton3D).get_bone_global_pose(idx).origin)
        var rest: Vector3 = recoil_inv * ((w.skeleton as Skeleton3D).global_transform * (w.skeleton as Skeleton3D).get_bone_global_rest(idx).origin)
        print("TRAVEL ", bone_name, " rest=", rest.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " posed=", posed.snapped(Vector3(0.0001, 0.0001, 0.0001)),
            " delta=", (posed - rest).snapped(Vector3(0.0001, 0.0001, 0.0001)))
    w.slide_pos = 0.0
    w.mag_visual_drop = 0.0
    w._apply_bone_poses()


func _print_geometry(label: String) -> void:
    var cam: Camera3D = player.camera
    var w = player.weapon
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
    var cam: Camera3D = player.camera
    var eye: Vector3 = cam.global_position
    var target_pos := Vector3(-4.0, 1.35, -18.0)
    var to_target: Vector3 = (target_pos - eye).normalized()
    player.yaw_target = atan2(-to_target.x, -to_target.z)
    player.pitch_target = asin(clampf(to_target.y, -1.0, 1.0))
    player.yaw = player.yaw_target
    player.pitch = player.pitch_target
    await get_tree().create_timer(0.25).timeout
    var before := ImpactFX.decals.size()
    player.weapon.force_fire_once()
    await get_tree().create_timer(1.0).timeout
    var targets := get_tree().get_nodes_in_group("targets")
    var health := -1.0
    if not targets.is_empty():
        health = targets[0].health
    print("PENTEST health=", health, " decals_before=", before, " decals_after=", ImpactFX.decals.size(), " mag=", player.weapon.mag, " chamber=", player.weapon.chamber)
    get_tree().quit()


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
