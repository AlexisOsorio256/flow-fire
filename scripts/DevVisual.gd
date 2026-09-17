extends Node

## Capturas deterministas (`--visualab`) y camara lenta (`--slowmo`).
##
## El A/B visual congela el tiempo (time_scale 0), clava fases, resortes y
## semillas, y reescribe cada frame lo que el juego randomiza: dos corridas
## identicas dan la misma imagen salvo el cambio que se evalua.

const GLOCK_SCRIPT := preload("res://scripts/Glock.gd")

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

const VISUAL_FLASH_ENERGY := 0.85      # pulso real calibrado de la boca

const VISUAL_LOADOUT := {"mag": 17, "chamber": 1, "reserve": 68}

var _player: CharacterBody3D
var _hud: CanvasLayer
var common: DevCommon

var _visual_pin := {}
var _visual_pin_active := false


func setup(main_node: Node3D, player_node: CharacterBody3D, hud_node: CanvasLayer, common_node) -> void:
    _player = player_node
    _hud = hud_node
    common = common_node


func run_visualab() -> void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    common.lock_viewport()
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
        await common.capture_view(path)
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
    p.camera.position = Vector3(0.0, VISUAL_EYE_Y, 0.0)
    p.camera.rotation = Vector3.ZERO
    p.camera.fov = VISUAL_FOV_HIP


func _visual_reset_weapon() -> void:
    var w = _player.weapon
    w.player_speed = 0.0
    w.player_velocity = Vector3.ZERO
    w.look_delta = Vector2.ZERO
    w._last_local_move = Vector2.ZERO
    w.viewmodel.sway = Vector2.ZERO
    w.viewmodel.bob_phase = 0.0
    w.viewmodel.idle_phase = 0.0
    w.sprinting = false
    w.sprint_blend = 0.0
    w.aim = false
    w.aim_blend = 0.0
    w.trigger_held = false
    w.trigger_ready = true
    w.trigger_latched = false
    w.trigger_visual = 0.0
    w.recoil.pos = Vector3.ZERO
    w.recoil.vel = Vector3.ZERO
    w.recoil.rot = Vector3.ZERO
    w.recoil.rot_vel = Vector3.ZERO
    w.recoil.arm_pos = Vector3.ZERO
    w.recoil.arm_vel = Vector3.ZERO
    w.recoil.arm_rot = Vector3.ZERO
    w.recoil.arm_rot_vel = Vector3.ZERO
    w.fx.timer = 0.0
    w.shot_pulse = 0.0
    w.reloading = false
    w.reload_elapsed = 0.0
    w.reload_total = 0.0
    w.reload_empty = false
    w.reload_pose_blend = 0.0
    w.reload_mag_seated = true
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
            w.shot_pulse = 1.0
            w.slide_pos = 0.010
            w.trigger_visual = 1.0
            w.fx.pop_flash()
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
## Los nombres son los del rig actual (full9mm 1Matzh): antes eran los del rig
## viejo de Cransh ("FPS_Pistol_*") y el aparcamiento fallaba en silencio,
## dejando la animación viva donde estuviera.
func _visual_park_animation(anim_name: String, t: float) -> void:
    var w = _player.weapon
    if w.viewmodel.arms_player != null:
        var arms_anim := "Idle"
        if anim_name == "Shoot":
            arms_anim = "Fire"
        elif anim_name == "Reload":
            arms_anim = "Reload"
        if w.viewmodel.play_anim(arms_anim, true):
            w.viewmodel.arms_player.seek(t, true)


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
    var port: Transform3D = w.viewmodel.ejection_port.global_transform
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
        "flash_energy": VISUAL_FLASH_ENERGY if w.fx.timer > 0.0 else 0.0,
        "post_time": t,
        "aim_amount": w.aim_blend,
        "shot_pulse": w.shot_pulse,
    }
    _visual_pin_active = true
    _process(0.0)
    if state == "shot" or state == "casing":
        await get_tree().process_frame
    if w.viewmodel.sight_marker != null and w.viewmodel.muzzle != null:
        var camv: Camera3D = _player.camera
        var pm: Vector2 = camv.unproject_position((w.viewmodel.sight_marker as Node3D).global_position)
        var pb: Vector2 = camv.unproject_position((w.viewmodel.muzzle as Node3D).global_position)
        print("VISUAL_MIRA ", state, " mira_px=(", snappedf(pm.x, 1.0), ",", snappedf(pm.y, 1.0),
            ") boca_px=(", snappedf(pb.x, 1.0), ",", snappedf(pb.y, 1.0), ")")


## Última escritura de cada frame mientras dura una captura: vuelve a clavar lo
## que el propio juego randomiza por frame.
func _process(_delta: float) -> void:
    if not _visual_pin_active:
        return
    var w = _player.weapon
    if w.fx != null and w.fx.muzzle_light != null:
        w.fx.muzzle_light.light_energy = float(_visual_pin["flash_energy"])
    _hud.post_mat.set_shader_parameter("time", float(_visual_pin["post_time"]))
    _hud.post_mat.set_shader_parameter("aim_amount", float(_visual_pin["aim_amount"]))
    _hud.post_mat.set_shader_parameter("exposure_pulse", float(_visual_pin["shot_pulse"]))


## Captura en cámara lenta del disparo y de la recarga: el ciclo de la corredera
## dura ~60 ms y a 10-14 FPS cabe entero entre dos frames, así que en slow motion
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
        await common.capture_view("%s/shot_%03d.png" % [dir, i])
        var cam: Camera3D = _player.camera
        # Cada capa del retroceso se mide por separado: no deben ser el mismo
        # movimiento disfrazado.
        var back: float = w.recoil.pos.z
        var pitch := rad_to_deg(w.recoil.rot.x)
        var arm_back: float = w.recoil.arm_pos.z
        var arm_pitch := rad_to_deg(w.recoil.arm_rot.x)
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


## Caja del cargador en pantalla: el cargador lo lleva la mano (hueso
## Magazine_924 del asset), asi que su caja es la del hueso en el mundo. El
## tamano es el del cargador medido en el asset (25.5 x 120 x 75 mm en su
## espacio). Aproximacion honesta para el slowmo, no geometria por vertice.
func _mag_screen_box() -> Dictionary:
    var w = _player.weapon
    var sk: Skeleton3D = w.viewmodel.arms_skeleton
    if sk == null:
        return {}
    var mag_bone := sk.find_bone("Magazine_924")
    if mag_bone < 0:
        return {}
    var bone_xf: Transform3D = sk.global_transform * sk.get_bone_global_pose(mag_bone)
    var posed := common.transform_aabb(AABB(Vector3(-0.013, -0.05, -0.038), Vector3(0.026, 0.12, 0.076)), bone_xf)
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


func _slowmo_reload() -> void:
    var dir := ProjectSettings.globalize_path("res://captures/reload")
    DirAccess.make_dir_recursive_absolute(dir)
    var w = _player.weapon
    w.set_aim(false)
    await get_tree().create_timer(0.6).timeout
    common.force_reloadable_state()
    w.start_reload()
    # 0.35 de escala: cada frame renderizado avanza ~30 ms, así que 60 frames
    # cubren la recarga entera (2.11 s) sin perder el momento del cargador.
    Engine.time_scale = 0.35
    var frames := 60
    var visible_samples := 0
    var biggest := 0.0
    for i in range(frames):
        await get_tree().process_frame
        await common.capture_view("%s/reload_%03d.png" % [dir, i])
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
