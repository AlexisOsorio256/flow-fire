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


func setup(main_node: Node3D, player_node: CharacterBody3D, hud_node: CanvasLayer) -> void:
    _main = main_node
    _player = player_node
    _hud = hud_node


func run_fpsbench() -> void:
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
    while index * step < 5.5:
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
    await get_tree().create_timer(0.5).timeout
    _print_geometry("hip")
    _player.weapon.set_aim(true)
    await get_tree().create_timer(0.8).timeout
    _print_geometry("ads")
    _player.weapon.set_aim(false)
    await get_tree().create_timer(0.4).timeout
    var travel := _print_bone_travel()
    # Durante la recarga: dónde acaba el cargador medido en frame de arma.
    _force_reloadable_state()
    _player.weapon.start_reload()
    await get_tree().create_timer(0.75).timeout
    _print_live_bones("reload")
    _finish_geometrydebug(travel)


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
            " drop=", snappedf(w.mag_visual_drop, 0.0001), " slide_pos=", snappedf(w.slide_pos, 0.0001))


## Comprueba que la corredera y el cargador viajan en la dirección medida: la
## corredera hacia atrás (+Z) y el cargador hacia abajo (-Y), en frame de arma.


func _print_bone_travel() -> Dictionary:
    var w = _player.weapon
    var recoil_inv: Transform3D = (w.recoil_node as Node3D).global_transform.affine_inverse()
    w.slide_pos = 0.039
    w.mag_visual_drop = 0.20
    w._apply_bone_poses()
    var deltas := {}
    for bone_name in ["Slide", "Magazine"]:
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
    w.mag_visual_drop = 0.0
    w._apply_bone_poses()
    return deltas


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


func _finish_geometrydebug(travel: Dictionary) -> void:
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
    var magazine: Vector3 = travel.get("Magazine", Vector3.ZERO)
    if magazine.y > -0.15:
        failures.append("el cargador no baja al recargar (delta %s)" % magazine)
    var passed := failures.is_empty()
    print("GEOMETRYDEBUG passed=", passed, " largo_m=", snappedf(w.measured_length_m, 0.0001),
        " caja=", size.snapped(Vector3(0.0001, 0.0001, 0.0001)),
        " slide=", slide.snapped(Vector3(0.001, 0.001, 0.001)),
        " cargador=", magazine.snapped(Vector3(0.001, 0.001, 0.001)))
    if not passed:
        push_error("GEOMETRYDEBUG falló: " + "; ".join(failures))
    get_tree().quit(0 if passed else 1)


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
