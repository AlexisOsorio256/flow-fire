extends Node3D

signal shot_fired
signal ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool)

## Rig completo del pack "Fps Rig" (J-Toastie, CC-BY 3.0): el Glock y los
## brazos comparten esqueleto y trae las animaciones Grip/Idle/Shoot/Reload.
## La pose de agarre es la del autor: nada de IK propio deformando el skin.
const MODEL_PATH := "res://assets/models/fps_rig.glb"
const MAG_SIZE := 17
const GUN_LENGTH := 0.186  # Glock 19 real: 186 mm de punta a punta.
const ADS_SIGHT_DISTANCE := 0.42  # Ojo -> mira trasera con el brazo extendido.
const ADS_SIGHT_DROP := 0.0  # La mira va clavada en el centro: donde apunta, impacta.
const HIP_POS := Vector3(0.0, 0.062, 0.0)  # Pose de lista: el arma va baja pero visible.
const GUN_TOP_OVER_ORIGIN := 0.035  # La corredera queda 3.5 cm sobre el origen.
# Ciclo mecánico de la corredera. Recorrido real de una Glock 19 (39 mm) y un
# impulso también real (4 m/s): el ciclo sale ~105 ms, el doble que los ~50 ms
# de una Glock de verdad, porque por debajo de eso el ojo (y un frame a 60 FPS)
# sólo ve un parpadeo. Sigue siendo frenético, pero se ve el viaje completo.
const SLIDE_TRAVEL := 0.039
const SLIDE_K := 1800.0        # rigidez del muelle recuperador
const SLIDE_C := 64.0          # amortización (zeta 0.755)
const SLIDE_IMPULSE := 4.05    # velocidad de retroceso tras el disparo (m/s)
const SLIDE_RESTITUTION := 0.25  # rebote contra el tope trasero
const SLIDE_EJECT_AT := 0.030  # el casquillo sale con el puerto ya abierto
# Tiempos de la animación "Reload" del autor (medidos sobre sus claves, ver
# tools/_rig_dump.gd): el cargador sale a los 0.40 s, vuelve a su sitio a los
# 1.10 s y la corredera se libera a los 1.70 s. La lógica usa esos mismos
# instantes, así que las manos y la mecánica no pueden contradecirse.
const RELOAD_MAG_OUT_T := 0.40
const RELOAD_MAG_IN_T := 1.10
const RELOAD_SLIDE_T := 1.70
const RELOAD_TACTICAL_END := 1.62  # corta antes de la liberación de corredera
const RELOAD_EMPTY_TOTAL := 2.11   # animación completa (2.042) + mezcla al idle
const RELOAD_TACTICAL_TOTAL := 1.80
# Pose de recarga: el tirador sube el arma y la gira para ver el brocal del
# cargador (es lo que hace de verdad). Sin esto la empuñadura queda por debajo
# del borde de la pantalla y el cargador sale del encuadre sin verse nunca.
const RELOAD_POSE_UP := 0.075     # sube el arma
const RELOAD_POSE_FWD := 0.045    # y la acerca algo a la cámara
const RELOAD_POSE_PITCH := 0.17   # gira el brocal hacia la cara
const RELOAD_POSE_ROLL := -0.30

var camera: Camera3D
var pose_root: Node3D
var recoil_node: Node3D
var muzzle: Node3D
var ejection_port: Node3D
var muzzle_flash: MeshInstance3D
var muzzle_flash_2: MeshInstance3D
var muzzle_light: OmniLight3D
var viewmodel_light: OmniLight3D

var brass_mat: StandardMaterial3D
var flash_mat: StandardMaterial3D

var mag := 17
var chamber := 1
var reserve := 68
var trigger_held := false
var trigger_ready := true
var trigger_latched := false
var trigger_reset_timer := 0.0

var slide_pos := 0.0
var slide_vel := 0.0
var slide_locked := false
var slide_extracted := false
var slide_open := false  # la corredera llegó a abrirse (para recamarar al cerrar)
var reload_pose_blend := 0.0

# Retroceso en capas independientes, cada una con su escala de tiempo:
#  1) mecánica: corredera/gatillo/cargador (la manda la lógica, ~80 ms)
#  2) arma en la mano: recoil_node girando sobre la MUÑECA (~240 ms)
#  3) brazos/viewmodel: pose_root entero, más lento y blando (~660 ms)
#  4) cámara: resortes de Player.gd, la más lenta
# No son el mismo movimiento disfrazado: cada capa tiene constante y amplitud
# propias, y se miden por separado en --shotcapture.
var wrist_pivot := Node3D.new()
var recoil_pos := Vector3.ZERO
var recoil_vel := Vector3.ZERO
var recoil_rot := Vector3.ZERO
var recoil_rot_vel := Vector3.ZERO
var arm_recoil_pos := Vector3.ZERO
var arm_recoil_vel := Vector3.ZERO
var arm_recoil_rot := Vector3.ZERO
var arm_recoil_rot_vel := Vector3.ZERO
var wrist_local := Vector3.ZERO  # punto de giro medido (frame de arma)

var aim := false
var sprinting := false
var aim_blend := 0.0
var sprint_blend := 0.0

var muzzle_timer := 0.0
var shot_pulse := 0.0

var reloading := false
var reload_elapsed := 0.0
var reload_total := 0.0
var reload_empty := false
var reload_slide_released := false
var reload_mag_seated := false
var reload_anim_cut := false
var mag_sound_out := false

var player_speed := 0.0
var look_delta := Vector2.ZERO
var bob_phase := 0.0
var idle_phase := 0.0
var sway := Vector2.ZERO
var player_velocity := Vector3.ZERO

var model_root: Node3D
var arms: Node3D
var gun_frame: Node3D
var skeleton: Skeleton3D
var glock_mesh: MeshInstance3D
var arms_mesh: MeshInstance3D
var animation_player: AnimationPlayer
var bone_slide := -1
var bone_trigger := -1
var bone_magazine := -1
var rest_slide := Transform3D.IDENTITY
var rest_trigger := Transform3D.IDENTITY
var rest_magazine := Transform3D.IDENTITY
var slide_axis := Vector3(0, 1, 0)
var model_units_per_meter := 0.241
var bone_units_per_meter := 0.241  # calibrado en runtime
var trigger_visual := 0.0
var sight_marker: Node3D
var ads_offset := Vector3(-0.17, 0.138, 0.105)
# Base real del arma medida en runtime sobre la malla del GLB (ver _measure_mesh).
var gun_frame_bind := Basis.IDENTITY
var bind_in_skeleton := Transform3D.IDENTITY
var mesh_to_weapon := Transform3D.IDENTITY
var gun_box := AABB()  # caja real de la malla en frame de arma
var measured_length_m := 0.0  # largo medido de la malla (m)
var alignment_ok := false     # la verificación de alineación pasó
var measured_marks := {}       # centroides de corredera/mira/cargador en frame de arma


func _ready() -> void:
    pose_root = Node3D.new()
    pose_root.name = "PoseRoot"
    add_child(pose_root)

    wrist_pivot.name = "WristPivot"
    pose_root.add_child(wrist_pivot)
    recoil_node = Node3D.new()
    recoil_node.name = "RecoilNode"
    wrist_pivot.add_child(recoil_node)

    _build_materials()
    _build_viewmodel_light()
    _build_model()
    _setup_bones()
    _emit_ammo()


## Luces del viewmodel: el arma vive en un interior oscuro y con su albedo real
## (polímero ~0.08) se leía como una mancha negra: medido, 5/255 de luminancia
## media sobre los píxeles del arma. Dos luces cortas y sin sombras (clave
## arriba-izquierda y relleno desde la cámara) la definen sin tocar la escena.
## Cuelgan de pose_root para que acompañen al arma en recarga y apuntado.
func _build_viewmodel_light() -> void:
    viewmodel_light = OmniLight3D.new()
    viewmodel_light.name = "ViewmodelKey"
    viewmodel_light.light_color = Color(0.94, 0.96, 1.0)
    viewmodel_light.light_energy = 2.9
    viewmodel_light.omni_range = 1.5
    viewmodel_light.omni_attenuation = 1.35
    viewmodel_light.shadow_enabled = false
    # Detrás y arriba: la cara que ve la cámara al apuntar (el dorso de la
    # corredera y la mira) tiene que estar iluminada, o el punto de mira se lee
    # negro y no se puede apuntar con él.
    viewmodel_light.position = Vector3(-0.30, 0.26, 0.42)
    pose_root.add_child(viewmodel_light)

    var fill := OmniLight3D.new()
    fill.name = "ViewmodelFill"
    fill.light_color = Color(1.0, 0.94, 0.86)
    fill.light_energy = 0.95
    fill.omni_range = 1.3
    fill.omni_attenuation = 1.2
    fill.shadow_enabled = false
    fill.position = Vector3(0.28, -0.08, 0.46)
    pose_root.add_child(fill)


func setup(cam: Camera3D) -> void:
    camera = cam
    _compute_ads_offset()
    # Los brazos se montan aqui y no en _ready porque necesitan la camara para
    # anclarse, y en _ready todavia es null: Player llama a setup() despues de
    # add_child.
    _install_arms()


func set_aim(value: bool) -> void:
    aim = value


func set_sprint(value: bool) -> void:
    sprinting = value


func set_motion(speed: float, local_move: Vector2, look: Vector2) -> void:
    player_speed = speed
    look_delta = look
    _last_local_move = local_move


var _last_local_move := Vector2.ZERO


func press_trigger() -> void:
    trigger_held = true


func release_trigger() -> void:
    trigger_held = false


func force_fire_once() -> void:
    if _can_fire():
        _fire()


func start_reload() -> bool:
    if reloading or reserve <= 0:
        return false
    if chamber > 0 and mag >= MAG_SIZE:
        return false
    reloading = true
    reload_elapsed = 0.0
    # Recarga en vacío = no hay cartucho en recámara: hay que soltar la
    # corredera para alimentarlo. Antes exigía además slide_locked, así que una
    # recarga con la recámara vacía y la corredera en batería dejaba el arma
    # cargada pero sin cartucho listo (mag=17, chamber=0).
    reload_empty = chamber <= 0
    # La animación del autor se reproduce a velocidad 1 (es su cadencia, y con
    # ella las claves caen donde él las puso). La recarga táctica conserva la
    # recámara, así que se corta antes de la liberación de corredera: la
    # animación nunca enseña algo que la mecánica no esté haciendo.
    reload_total = RELOAD_EMPTY_TOTAL if reload_empty else RELOAD_TACTICAL_TOTAL
    reload_slide_released = false
    reload_mag_seated = false
    reload_anim_cut = false
    aim = false
    trigger_held = false
    _play_reload_animation()
    _emit_ammo()
    return true


## Arranca la animación de recarga del autor sin encolar el idle: el final lo
## decide la lógica (corte táctico o mezcla al terminar).
func _play_reload_animation() -> void:
    if animation_player == null:
        return
    var resolved := _resolve_animation("Reload")
    if resolved != "":
        animation_player.play(resolved, -1.0, 1.0)


func _blend_to_idle(blend: float) -> void:
    if animation_player == null:
        return
    var idle := _resolve_animation("Idle")
    if idle == "":
        idle = _resolve_animation("Grip")
    if idle != "":
        animation_player.play(idle, blend)


func _can_fire() -> bool:
    return not reloading and chamber > 0 and absf(slide_pos) < 0.0025


func _process(delta: float) -> void:
    _update_trigger(delta)
    _update_slide(delta)
    _update_recoil(delta)
    _update_reload(delta)
    _update_pose(delta)
    _apply_bone_poses()

    muzzle_timer = maxf(0.0, muzzle_timer - delta)
    shot_pulse = maxf(0.0, shot_pulse - delta * 8.0)

    var flash_visible := muzzle_timer > 0.0
    if muzzle_flash != null:
        muzzle_flash.visible = flash_visible
    if muzzle_flash_2 != null:
        muzzle_flash_2.visible = flash_visible
    if muzzle_light != null:
        muzzle_light.light_energy = randf_range(5.5, 10.5) if flash_visible else 0.0


func _update_trigger(delta: float) -> void:
    trigger_visual += ((1.0 if trigger_held else 0.0) - trigger_visual) * (1.0 - exp(-18.0 * delta))

    if trigger_held and trigger_ready and _can_fire():
        _fire()
        return

    # Gatillo en seco: con la recámara vacía y la corredera en batería la aguja
    # golpea en vacío. Antes no sonaba nada y el arma parecía muerta.
    if trigger_held and trigger_ready and not reloading and chamber <= 0 and not slide_locked:
        trigger_ready = false
        trigger_latched = true
        trigger_reset_timer = 0.075
        GameAudio.play_2d("empty")

    if not trigger_held:
        if trigger_latched:
            trigger_reset_timer -= delta
            if trigger_reset_timer <= 0.0:
                trigger_ready = true
                trigger_latched = false
        else:
            trigger_ready = true


func _fire() -> void:
    chamber -= 1
    trigger_ready = false
    trigger_latched = true
    trigger_reset_timer = 0.075
    slide_extracted = false
    slide_open = false
    slide_vel += SLIDE_IMPULSE
    shot_pulse = 1.0

    # 2) arma en la mano: impulso corto y recuperación rápida (k=700, zeta 0.75
    #    -> pico a los ~41 ms y vuelta a batería en ~0.24 s). Antes el pico era
    #    de 12 grados de cabeceo: medido y exagerado.
    recoil_vel += Vector3((randf() - 0.5) * 0.06, 0.10, 0.66 + randf() * 0.06)
    recoil_rot_vel += Vector3((4.7 + randf() * 0.7) * (1.0 if randf() > 0.5 else 1.0), (randf() - 0.5) * 0.55, (randf() - 0.5) * 0.9)
    # 3) brazos: el mismo disparo, pero el hombro absorbe en otra escala (k=90).
    arm_recoil_vel += Vector3((randf() - 0.5) * 0.03, 0.05, 0.20 + randf() * 0.03)
    arm_recoil_rot_vel += Vector3(0.47 + randf() * 0.12, 0.0, (randf() - 0.5) * 0.16)

    muzzle_timer = 0.04
    muzzle_flash.rotation.z = randf_range(0.0, TAU)
    muzzle_flash.scale = Vector3.ONE * randf_range(0.85, 1.35)
    muzzle_flash_2.rotation.z = randf_range(0.0, TAU)
    muzzle_flash_2.scale = Vector3.ONE * randf_range(0.7, 1.2)

    GameAudio.play_shot()
    _play_animation("Shoot", 1.4)

    var origin := muzzle.global_position
    var cam_fwd := -camera.global_transform.basis.z.normalized()
    var aim_point := camera.global_position + cam_fwd * 46.0
    var dir := (aim_point - origin).normalized()
    var right := camera.global_transform.basis.x.normalized()
    var up := camera.global_transform.basis.y.normalized()
    var move_amount := clampf(player_speed / 4.35, 0.0, 1.0)
    var spread := 0.00055 if aim_blend > 0.55 else 0.0036 + move_amount * 0.0052
    dir = (dir + right * randf_range(-spread, spread) + up * randf_range(-spread, spread)).normalized()

    Ballistics.fire(origin, dir, 372.0, 0.42)
    ImpactFX.spawn_muzzle_smoke(origin, cam_fwd)

    emit_signal("shot_fired")
    _emit_ammo()


func _update_slide(delta: float) -> void:
    if slide_locked:
        slide_pos = SLIDE_TRAVEL
        slide_vel = 0.0
    else:
        # Se integra por subpasos en vez de usar Springs porque los avisos
        # ("abrió", "volvió a batería", "tocó extraer") hay que verlos DENTRO del
        # recorrido: a pocos FPS el ciclo entero de la corredera cabe en un frame
        # y mirando solo el estado final no se recamarraba ni salía el casquillo.
        # El subpaso de 2.5 ms es estable para k=2560 y c=70.8.
        const SUBSTEP := 0.0025
        var span := minf(delta, SUBSTEP * 64.0)
        var steps := maxi(1, ceili(span / SUBSTEP))
        var h := span / float(steps)
        for _i in range(steps):
            slide_vel += (-SLIDE_K * slide_pos - SLIDE_C * slide_vel) * h
            slide_pos += slide_vel * h
            if slide_pos < 0.0:
                slide_pos = 0.0
                slide_vel = maxf(0.0, slide_vel)
            if slide_pos > SLIDE_TRAVEL:
                # Tope trasero real: la corredera golpea el armazón y rebota.
                slide_pos = SLIDE_TRAVEL
                slide_vel = -slide_vel * SLIDE_RESTITUTION

            if not slide_extracted and slide_pos > SLIDE_EJECT_AT:
                slide_extracted = true
                _spawn_shell()

            # Alimentar el siguiente cartucho cuando la corredera vuelve a
            # batería. Se detecta por evento (abrió y volvió a cerrar) y no por
            # velocidad: la velocidad oscila alrededor de cero al asentarse.
            if slide_pos > 0.02:
                slide_open = true
            if slide_open and slide_pos <= 0.001 and chamber <= 0 and mag > 0:
                slide_open = false
                mag -= 1
                chamber = 1
                _emit_ammo()

    if slide_pos > SLIDE_TRAVEL * 0.87 and mag <= 0 and chamber <= 0 and not reloading:
        slide_locked = true
        slide_pos = SLIDE_TRAVEL
        slide_vel = 0.0
        GameAudio.play_2d("slide")


func _update_recoil(delta: float) -> void:
    # Capa 2: el arma gira en la mano sobre la muñeca. El pivote va detrás y
    # debajo de la empuñadura (medido de la caja del arma), así que la boca sube
    # mientras la empuñadura casi no se mueve: es lo que hace un retroceso real y
    # lo que antes se sentía "forzado" (giro sobre el centro del arma).
    var pos := Springs.vector(recoil_pos, recoil_vel, 700.0, 39.7, delta)
    recoil_pos = pos[0]
    recoil_vel = pos[1]
    var rot := Springs.vector(recoil_rot, recoil_rot_vel, 700.0, 39.7, delta)
    recoil_rot = rot[0]
    recoil_rot_vel = rot[1]
    recoil_pos = Vector3(clampf(recoil_pos.x, -0.03, 0.03), clampf(recoil_pos.y, -0.03, 0.03), clampf(recoil_pos.z, -0.03, 0.045))
    recoil_rot = Vector3(clampf(recoil_rot.x, -0.16, 0.16), clampf(recoil_rot.y, -0.08, 0.08), clampf(recoil_rot.z, -0.1, 0.1))
    recoil_node.position = -wrist_local + recoil_pos
    recoil_node.rotation = recoil_rot
    wrist_pivot.position = wrist_local
    wrist_pivot.rotation = recoil_rot

    # Capa 3: brazos y viewmodel entero, más lento y blando.
    var arm_pos := Springs.vector(arm_recoil_pos, arm_recoil_vel, 90.0, 15.2, delta)
    arm_recoil_pos = arm_pos[0]
    arm_recoil_vel = arm_pos[1]
    var arm_rot := Springs.vector(arm_recoil_rot, arm_recoil_rot_vel, 90.0, 15.2, delta)
    arm_recoil_rot = arm_rot[0]
    arm_recoil_rot_vel = arm_rot[1]
    arm_recoil_pos = Vector3(clampf(arm_recoil_pos.x, -0.02, 0.02), clampf(arm_recoil_pos.y, -0.02, 0.02), clampf(arm_recoil_pos.z, -0.02, 0.03))
    arm_recoil_rot = Vector3(clampf(arm_recoil_rot.x, -0.08, 0.08), 0.0, clampf(arm_recoil_rot.z, -0.04, 0.04))


func _update_reload(delta: float) -> void:
    if not reloading:
        return
    reload_elapsed += delta

    # El sonido va en el instante en que ocurre el gesto, no al empezar.
    if not mag_sound_out and reload_elapsed >= RELOAD_MAG_OUT_T:
        mag_sound_out = true
        GameAudio.play_2d("magout", 0.0, randf_range(0.95, 1.05))

    if not reload_mag_seated and reload_elapsed >= RELOAD_MAG_IN_T:
        _seat_reload_mag()
        GameAudio.play_2d("magin", 0.0, randf_range(0.95, 1.05))

    # Corredera: en una recarga en vacío se libera a mano en el mismo momento en
    # que la animación del autor la suelta.
    if reload_empty and not reload_slide_released and reload_elapsed >= RELOAD_SLIDE_T:
        reload_slide_released = true
        slide_locked = false
        slide_pos = SLIDE_TRAVEL
        slide_vel = -4.2
        GameAudio.play_2d("slide", 1.0)

    # La pose sube con la mano (0.05-0.30 s), se mantiene mientras está el
    # cargador fuera y baja cuando ya está dentro.
    var up_t := clampf((reload_elapsed - 0.05) / 0.25, 0.0, 1.0)
    var down_t := clampf((reload_elapsed - RELOAD_MAG_IN_T) / 0.35, 0.0, 1.0)
    reload_pose_blend = _smooth(up_t) * (1.0 - _smooth(down_t))

    # Recarga táctica: la recámara conserva su cartucho, así que no se toca la
    # corredera y la animación se corta antes de ese gesto.
    if not reload_empty and not reload_anim_cut and reload_elapsed >= RELOAD_TACTICAL_END:
        reload_anim_cut = true
        _blend_to_idle(0.16)

    if reload_elapsed >= reload_total:
        _finish_reload()


func _seat_reload_mag() -> void:
    if reload_mag_seated:
        return
    # El reserve es un conteo de cartuchos: el cargador retirado vuelve al pool.
    var pool := reserve + mag
    var loaded := mini(MAG_SIZE, pool)
    reserve = pool - loaded
    mag = loaded
    reload_mag_seated = true
    _emit_ammo()


func _finish_reload() -> void:
    if not reload_mag_seated:
        _seat_reload_mag()
    reloading = false
    _blend_to_idle(0.14)
    _emit_ammo()


func _update_pose(delta: float) -> void:
    idle_phase += delta
    var target_sprint := 1.0 if sprinting else 0.0
    sprint_blend += (target_sprint - sprint_blend) * (1.0 - exp(-5.5 * delta))
    var target_aim := (1.0 if aim else 0.0) * (1.0 - sprint_blend)
    aim_blend += (target_aim - aim_blend) * (1.0 - exp(-9.0 * delta))

    var look_x := clampf(look_delta.x, -12.0, 12.0) * 0.0015
    var look_y := clampf(look_delta.y, -12.0, 12.0) * 0.0015
    sway.x += (-look_x - sway.x) * (1.0 - exp(-10.0 * delta))
    sway.y += (-look_y - sway.y) * (1.0 - exp(-10.0 * delta))
    sway.x = clampf(sway.x, -0.012, 0.012)
    sway.y = clampf(sway.y, -0.012, 0.012)

    if player_speed > 0.25:
        bob_phase += delta * (1.8 + player_speed * 1.45)

    var hip_pos := HIP_POS
    var ads_pos := ads_offset
    var sprint_pos := Vector3(0.05, -0.135, -0.02)
    var hip_rot := Vector3.ZERO
    var ads_rot := Vector3.ZERO
    var sprint_rot := Vector3(deg_to_rad(-14.0), deg_to_rad(-5.0), deg_to_rad(5.0))

    var carry_pos := hip_pos.lerp(sprint_pos, sprint_blend)
    var carry_rot := hip_rot.lerp(sprint_rot, sprint_blend)
    var pos := carry_pos.lerp(ads_pos, aim_blend)
    var rot := carry_rot.lerp(ads_rot, aim_blend)

    var move_norm := clampf(player_speed / 4.35, 0.0, 1.0)
    pos.x += cos(bob_phase * 0.5) * 0.0045 * move_norm + sway.x * (1.0 - aim_blend * 0.65)
    pos.y += sin(bob_phase) * 0.0065 * move_norm + sin(idle_phase * 1.05) * 0.0016 * (1.0 - aim_blend * 0.55) + sway.y * (1.0 - aim_blend * 0.65)
    var move_x := clampf(_last_local_move.x, -1.0, 1.0)
    var move_y := clampf(_last_local_move.y, -1.0, 1.0)
    pos.x -= move_x * 0.02 * (1.0 - aim_blend * 0.5)
    pos.y -= absf(move_y) * 0.008 * (1.0 - aim_blend * 0.5)

    pos += arm_recoil_pos
    rot += arm_recoil_rot
    rot.x += sway.y * 0.5 + sin(idle_phase * 1.05) * 0.0025 * (1.0 - aim_blend * 0.6) - move_y * 0.008
    rot.y += sway.x * 0.5 + sin(idle_phase * 0.73 + 1.0) * 0.0020 * (1.0 - aim_blend * 0.6)
    rot.z += -move_x * 0.012 - sin(bob_phase) * 0.012 * sprint_blend
    pos.x = clampf(pos.x, -0.30, 0.30)
    pos.y = clampf(pos.y, -0.30, 0.18)
    pos.z = clampf(pos.z, -0.20, 0.15)
    rot.x = clampf(rot.x, -0.35, 0.35)
    rot.y = clampf(rot.y, -0.35, 0.35)
    rot.z = clampf(rot.z, -0.25, 0.25)

    # Pose de recarga: sube y gira el arma para que el brocal entre en pantalla.
    # Las manos van en el mismo rig, así que suben con ella: no hay desincronía.
    pos.y += reload_pose_blend * RELOAD_POSE_UP
    pos.z += reload_pose_blend * RELOAD_POSE_FWD
    rot.x += reload_pose_blend * RELOAD_POSE_PITCH
    rot.z += reload_pose_blend * RELOAD_POSE_ROLL
    pose_root.position = pos
    pose_root.rotation = rot


func _spawn_shell() -> void:
    if not is_instance_valid(get_tree().current_scene):
        return
    var shell = preload("res://scripts/Shell.gd").new()
    shell.mass = 0.008
    shell.collision_layer = 2
    shell.collision_mask = 1
    shell.continuous_cd = true

    # Vaina del 9x19 real: 19,15 mm de largo y 9,6 mm de culote. Nada de
    # agrandarla para que se vea: la hace visible su brillo, su giro y el sitio
    # por donde sale, no el tamaño.
    var cylinder := CylinderMesh.new()
    cylinder.height = 0.01915
    cylinder.top_radius = 0.0048
    cylinder.bottom_radius = 0.0048
    cylinder.radial_segments = 12
    cylinder.material = brass_mat
    var shell_mesh := MeshInstance3D.new()
    shell_mesh.mesh = cylinder
    # El cilindro nace con el eje en Y: la vaina sale tumbada, con el eje a lo
    # largo del cañón (la boca hacia delante y el culote donde la sujeta el
    # extractor). Antes salía de pie, atravesada.
    shell_mesh.rotation.x = deg_to_rad(-90.0)
    shell.add_child(shell_mesh)

    var shape := CylinderShape3D.new()
    shape.height = 0.01915
    shape.radius = 0.0048
    var collider := CollisionShape3D.new()
    collider.shape = shape
    collider.rotation.x = deg_to_rad(-90.0)
    shell.add_child(collider)

    var physics_mat := PhysicsMaterial.new()
    physics_mat.bounce = 0.52
    physics_mat.friction = 0.45
    shell.physics_material_override = physics_mat
    # Rozamiento del aire sobre una vaina de 8 g: frena en vuelo en vez de
    # cruzar la pantalla de lado a lado en 90 ms (que es lo que hacía).
    shell.linear_damp = 0.9
    shell.angular_damp = 0.5

    get_tree().current_scene.add_child(shell)
    # Grupo de medición: la herramienta de captura en cámara lenta sigue a los
    # casquillos para comprobar que se ven salir (igual que "targets").
    shell.add_to_group("shells")
    shell.global_transform = ejection_port.global_transform
    var basis := ejection_port.global_transform.basis
    # El puerto está en la cara derecha del arma: el casquillo sale a la derecha
    # (+X), arriba (+Y) y algo hacia atrás (+Z, que es la cola del arma).
    # La vaina sale empujada por el extractor: hacia atrás hereda parte de la
    # velocidad real de la corredera, y el expulsor la tira a la derecha y
    # arriba. El giro es rápido (una vaina recién expulsada voltea).
    var local_vel := Vector3(1.5 + randf() * 0.7, 1.3 + randf() * 0.6, maxf(0.6, slide_vel * 0.35))
    shell.linear_velocity = basis * local_vel + player_velocity * 0.8
    shell.angular_velocity = Vector3(randf_range(-34.0, 34.0), randf_range(-34.0, 34.0), randf_range(-34.0, 34.0))


func _emit_ammo() -> void:
    ammo_changed.emit(mag, chamber, reserve, reloading)


func _smooth(t: float) -> float:
    return t * t * (3.0 - 2.0 * t)


func _build_materials() -> void:
    # Los materiales del arma los construye GunMaterials (por nombre de
    # primitiva, con detalle procedural). Aquí sólo quedan el latón de los
    # casquillos y el material del fogonazo.
    # Latón pulido: albedo de metal real y sin emisión (una vaina caliente no
    # brilla; la hacía visible el brillo del entorno, no un truco).
    brass_mat = StandardMaterial3D.new()
    brass_mat.albedo_color = Color(0.86, 0.68, 0.30)
    brass_mat.metallic = 0.95
    brass_mat.roughness = 0.24

    flash_mat = StandardMaterial3D.new()
    flash_mat.albedo_texture = preload("res://assets/textures/muzzle_flash.png")
    flash_mat.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
    flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    flash_mat.emission_enabled = true
    flash_mat.emission = Color(1.0, 0.55, 0.15)
    flash_mat.emission_energy_multiplier = 5.0
    flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _build_model() -> void:
    var packed := load(MODEL_PATH) as PackedScene
    if packed == null:
        push_error("No se pudo cargar el modelo Glock riggeado")
        return
    model_root = packed.instantiate()
    model_root.name = "GlockModel"
    model_root.transform = Transform3D.IDENTITY
    recoil_node.add_child(model_root)

    skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
    glock_mesh = model_root.find_child("Glock19", true, false) as MeshInstance3D
    arms_mesh = model_root.find_child("ArmModel", true, false) as MeshInstance3D
    var bullet_mesh := model_root.find_child("Glock19_001", true, false) as MeshInstance3D
    if bullet_mesh != null:
        bullet_mesh.visible = false
    _apply_model_materials()
    _apply_arms_materials()
    _setup_animations()

    # El GLB no viene alineado con los ejes de Godot: el nodo Armature trae su
    # propia rotación y los bind poses otra distinta. En vez de suponer cuál es
    # la orientación "correcta", se mide la geometría real en runtime y se
    # corrige el modelo con esa medida (ver _measure_mesh).
    var measure := _measure_mesh()
    if measure.get("ok", false):
        _align_model_with_mesh(measure)
        _build_reference_markers(measure)
    else:
        # Sin medida fiable no se inventa orientación: se avisa y se dejan los
        # marcadores en las cotas nominales de una Glock 19.
        push_error("No se pudo medir la malla del Glock: se usan cotas nominales")
        _build_reference_markers({})

    _install_pistol()


## Sustituye la malla de arma del rig viejo por la pistola de alta fidelidad,
## conservando brazos, esqueleto y animaciones.
##
## La OWK 19 es ya el arma por defecto. Se gano el puesto comparando con la
## misma camara: en ADS y con la corredera atras se leen las estrias de la
## corredera, el alza con sus puntos y el puerto de expulsion, donde el rig viejo
## es un bloque liso. Ademas su cargador lo mueve el hueso animado del autor, su
## boca/mira/puerto se miden sobre su propia geometria y sus texturas ocupan 38 MB
## en vez de 208.
##
## La malla vieja sigue en el GLB porque es de donde salen los BRAZOS y las cuatro
## animaciones, y se puede recuperar entera con --oldgun para seguir comparando.
func _install_pistol() -> void:
    if OS.get_cmdline_user_args().has("--oldgun"):
        print("GLOCK arma=rig_viejo (--oldgun)")
        return
    if not _build_high_fidelity_pistol():
        push_warning("Se conserva la malla de arma del rig viejo")
        return
    if glock_mesh != null:
        glock_mesh.visible = false
    print("GLOCK arma=owk19")



## Mide la malla tal como viene del GLB: vértices en su espacio de bind, caja
## envolvente y base real del arma. No se asume ninguna orientación: el eje más
## largo de la malla es el del cañón, el mediano la altura (corredera arriba,
## empuñadura abajo) y el más corto la anchura. Los signos salen de la propia
## geometría, porque la empuñadura está en la mitad trasera y cuelga hacia abajo.
func _measure_mesh() -> Dictionary:
    var result := {"ok": false, "verts": PackedVector3Array(), "frame": Basis.IDENTITY, "length": 0.0, "aabb": AABB()}
    var bind_verts := _bind_vertices()
    if bind_verts.is_empty() or skeleton == null or glock_mesh == null or glock_mesh.skin == null:
        push_error("La malla del Glock no tiene vértices: imposible medir su base")
        return result

    var bind_in_model := _bind_in_model()
    var verts := PackedVector3Array()
    verts.resize(bind_verts.size())
    for i in range(bind_verts.size()):
        verts[i] = bind_in_model * bind_verts[i]

    var box := _bounds(verts)
    var size := box.size

    # 1) Eje del cañón: la dimensión mayor de la malla (con signo por decidir).
    var axis_len := 0
    for i in range(1, 3):
        if size[i] > size[axis_len]:
            axis_len = i
    var axis := Vector3.ZERO
    axis[axis_len] = 1.0
    var helper := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
    var x0 := helper.cross(axis).normalized()
    var y0 := axis.cross(x0).normalized()
    var base0 := Basis(x0, y0, axis)

    # 2) Balanceo: se busca el ángulo que MINIMIZA el área de la sección
    # perpendicular al cañón. La sección del arma es muy alargada (alto contra
    # ancho), así que el mínimo cae en la orientación alineada. Este rig venía
    # con ~15 grados de balanceo y por eso la caja salía de 59 mm de ancho.
    var best_angle := 0.0
    var best_area := INF
    var best_lo := Vector2.ZERO
    var best_hi := Vector2.ZERO
    for step in range(0, 90):
        var angle := deg_to_rad(float(step))
        var probe := base0 * Basis(Vector3.BACK, angle)
        var inv := probe.inverse()
        var lo := Vector2(INF, INF)
        var hi := Vector2(-INF, -INF)
        for v in verts:
            var local := inv * v
            lo.x = minf(lo.x, local.x)
            lo.y = minf(lo.y, local.y)
            hi.x = maxf(hi.x, local.x)
            hi.y = maxf(hi.y, local.y)
        var area := (hi.x - lo.x) * (hi.y - lo.y)
        if area < best_area:
            best_area = area
            best_angle = angle
            best_lo = lo
            best_hi = hi
    var frame := base0 * Basis(Vector3.BACK, best_angle)
    # El mínimo de área tiene ambigüedad de 90 grados: el eje VERTICAL es el
    # largo de la sección (el arma es mucho más alta que ancha).
    if (best_hi.x - best_lo.x) > (best_hi.y - best_lo.y):
        frame = frame * Basis(Vector3.BACK, PI * 0.5)

    # 3) Signos por física del arma: la mira va ENCIMA de la corredera y la
    # empuñadura DETRÁS. Nada de suposiciones.
    var to_frame := frame.inverse()
    var slide_mid := to_frame * _centroid(_surface_vertices("Slide"))
    var sight_mid := to_frame * _centroid(_surface_vertices("White"))
    var magazine_mid := to_frame * _centroid(_surface_vertices("Magazine"))
    var up := frame.y
    var forward := frame.z
    if (sight_mid - slide_mid).y < 0.0:
        up = -up
    if (magazine_mid - slide_mid).z > 0.0:
        forward = -forward
    var right := up.cross(-forward).normalized()
    var gun_frame := Basis(right, up, -forward)

    var final_inv := gun_frame.inverse()
    var f_lo := Vector3(INF, INF, INF)
    var f_hi := Vector3(-INF, -INF, -INF)
    for v in verts:
        var local := final_inv * v
        f_lo = f_lo.min(local)
        f_hi = f_hi.max(local)
    result["ok"] = true
    result["verts"] = verts
    result["frame"] = gun_frame
    result["frame_box"] = AABB(f_lo, f_hi - f_lo)
    # El largo del arma es la dimensión mayor de la caja, sin depender del giro.
    result["length"] = maxf(size.x, maxf(size.y, size.z))
    result["aabb"] = box
    return result


## Bind -> modelo usando el skin de los BRAZOS (su convención es la del autor).
func _arms_bind_in_model() -> Transform3D:
    if arms_mesh == null or arms_mesh.skin == null:
        return Transform3D.IDENTITY
    for i in range(arms_mesh.skin.get_bind_count()):
        var bind_name := arms_mesh.skin.get_bind_name(i)
        if bind_name == "":
            continue
        var bone := skeleton.find_bone(bind_name)
        if bone < 0:
            continue
        return _local_chain(skeleton, model_root) * skeleton.get_bone_global_rest(bone) * arms_mesh.skin.get_bind_pose(i)
    return Transform3D.IDENTITY


## Caja envolvente de `box` expresada en otro sistema (sus 8 esquinas).
func _box_in_frame(box: AABB, transform: Transform3D) -> AABB:
    var result := AABB()
    var first := true
    var mn := box.position
    var mx := box.position + box.size
    for xi in [0.0, 1.0]:
        for yi in [0.0, 1.0]:
            for zi in [0.0, 1.0]:
                var corner := Vector3(lerpf(mn.x, mx.x, xi), lerpf(mn.y, mx.y, yi), lerpf(mn.z, mx.z, zi))
                var p := transform * corner
                if first:
                    result = AABB(p, Vector3.ZERO)
                    first = false
                else:
                    result = result.expand(p)
    return result


## Centroide de una lista de puntos.
func _centroid(points: PackedVector3Array) -> Vector3:
    var sum := Vector3.ZERO
    for p in points:
        sum += p
    return sum / float(maxi(points.size(), 1))


## Vértices de una primitiva concreta del arma, en espacio de modelo.
func _surface_vertices(surface_name: String) -> PackedVector3Array:
    var out := PackedVector3Array()
    if glock_mesh == null or glock_mesh.mesh == null or skeleton == null or glock_mesh.skin == null:
        return out
    var bind_in_model := _bind_in_model()
    for i in range(glock_mesh.mesh.get_surface_count()):
        if glock_mesh.mesh.surface_get_name(i) != surface_name:
            continue
        var arrays := glock_mesh.mesh.surface_get_arrays(i)
        if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
            continue
        for v in arrays[Mesh.ARRAY_VERTEX]:
            out.append(bind_in_model * v)
    return out


## Vértices de la malla del arma en su espacio de bind.
func _bind_vertices() -> PackedVector3Array:
    var verts := PackedVector3Array()
    if glock_mesh == null or glock_mesh.mesh == null:
        return verts
    for surface in range(glock_mesh.mesh.get_surface_count()):
        var arrays := glock_mesh.mesh.surface_get_arrays(surface)
        if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
            continue
        verts.append_array(arrays[Mesh.ARRAY_VERTEX])
    return verts


## Cadena del hueso raíz del arma: bind -> espacio del modelo.
func _bind_in_model() -> Transform3D:
    var root_bone := skeleton.find_bone("Root")
    if root_bone < 0:
        push_error("El rig no tiene hueso Root: no se puede medir el arma")
        return Transform3D.IDENTITY
    var root_name := skeleton.get_bone_name(root_bone)
    var bind_index := -1
    for i in range(glock_mesh.skin.get_bind_count()):
        if glock_mesh.skin.get_bind_name(i) == root_name:
            bind_index = i
            break
    if bind_index < 0:
        push_error("Ningún bind del arma se llama %s" % root_name)
        return Transform3D.IDENTITY
    bind_in_skeleton = skeleton.get_bone_global_rest(root_bone) * glock_mesh.skin.get_bind_pose(bind_index)
    return _local_chain(skeleton, model_root) * bind_in_skeleton


## Corrige model_root para que la malla quede en el frame del arma:
## -Z adelante (boca), +Y arriba (corredera) y +X derecha, con la escala real
## (Glock 19 = 186 mm de largo). La corrección sale de la cadena medida
## hueso/bind/armature, no de números fijos.
func _align_model_with_mesh(measure: Dictionary) -> void:
    if model_root == null or skeleton == null or glock_mesh == null or glock_mesh.skin == null:
        push_error("No se pudo medir la base del arma: falta esqueleto o skin")
        return
    var bind_in_model := _bind_in_model()
    gun_frame_bind = measure["frame"]

    # Cotas reales de una Glock 19 (m): ancho, alto, largo. El bind de este rig
    # es anisótropo (una conversión FBX), así que la escala se aplica por eje
    # llevando la caja medida en el frame del arma a estas cotas: así se corrige
    # la deformación y el arma mide lo que mide una Glock de verdad.
    var target := Vector3(0.0296, 0.1286, GUN_LENGTH)
    var frame_box: AABB = measure["frame_box"]
    var axis_scale := Vector3(
        target.x / maxf(frame_box.size.x, 0.000001),
        target.y / maxf(frame_box.size.y, 0.000001),
        target.z / maxf(frame_box.size.z, 0.000001)
    )
    model_root.basis = Basis.IDENTITY.scaled(axis_scale) * gun_frame_bind.inverse()
    # Centrado: el origen del rig nuevo no cae en el centro del arma (quedaba
    # 15 cm a la derecha). Se centra lateral y longitudinalmente y se deja la
    # parte alta de la corredera 3.5 cm sobre el origen, como referencia de la
    # línea de miras.
    var centred := _box_in_frame(_bounds(measure["verts"]), model_root.basis)
    var box_centre := centred.position + centred.size * 0.5
    model_root.position = Vector3(
        -box_centre.x,
        GUN_TOP_OVER_ORIGIN - (centred.position.y + centred.size.y),
        -box_centre.z
    )
    mesh_to_weapon = model_root.transform * bind_in_model
    # Los centroides medidos vienen en espacio de modelo: a frame de arma se
    # pasan con la transformación del modelo.
    measured_marks = {
        "slide": model_root.transform * _centroid(_surface_vertices("Slide")),
        "sight": model_root.transform * _centroid(_surface_vertices("White")),
        "magazine": model_root.transform * _centroid(_surface_vertices("Magazine")),
    }
    model_units_per_meter = 1.0 / maxf(axis_scale.z, 0.000001)
    measured_length_m = GUN_LENGTH
    print("GLOCK_MEDIDA largo_m=", snappedf(measured_length_m, 0.0001),
        " escala_ejes=", axis_scale.snapped(Vector3(0.0001, 0.0001, 0.0001)))
    _verify_alignment()


func _apply_arms_materials() -> void:
    if arms_mesh == null or arms_mesh.mesh == null:
        return
    var materials := GunMaterials.build()
    for i in range(arms_mesh.mesh.get_surface_count()):
        var surface_name: String = arms_mesh.mesh.surface_get_name(i)
        if materials.has(surface_name):
            arms_mesh.set_surface_override_material(i, materials[surface_name])
    arms_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Animaciones del pack: la pose de agarre y el idle son del autor (nada de IK
## deformando el skin). Este AnimationPlayer se procesa ANTES que el script, así
## que las poses del arma que escribe el juego siguen ganando.
func _setup_animations() -> void:
    animation_player = model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
    if animation_player == null:
        push_warning("El rig no trae AnimationPlayer: los brazos quedarán en bind")
        return
    animation_player.process_priority = -10
    print("GLOCK animaciones=", animation_player.get_animation_list())
    var idle := _resolve_animation("Idle")
    var grip := _resolve_animation("Grip")
    if idle != "":
        animation_player.play(idle)
    elif grip != "":
        animation_player.play(grip)


## Reproduce una animación del rig una vez y vuelve al idle.
func _play_animation(anim_name: String, speed: float = 1.0) -> void:
    if animation_player == null:
        return
    var resolved := _resolve_animation(anim_name)
    if resolved == "":
        return
    animation_player.play(resolved, -1.0, speed)
    var idle := _resolve_animation("Idle")
    if idle == "":
        idle = _resolve_animation("Grip")
    if idle != "":
        animation_player.queue(idle)


## El glTF importa las animaciones con prefijo ("Armature|Shoot"): se buscan por
## sufijo para no depender de cómo las nombre el exportador.
func _resolve_animation(short_name: String) -> String:
    if animation_player == null:
        return ""
    if animation_player.has_animation(short_name):
        return short_name
    for candidate in animation_player.get_animation_list():
        if candidate.ends_with("|" + short_name) or candidate.ends_with(short_name):
            return candidate
    return ""


## Comprobación en runtime de que la corrección quedó bien: la malla tiene que
## quedar en el frame del arma (base uniforme, sin rotación) y con la mano
## correcta (en una Glock el cierre de corredera va al lado izquierdo).
func _verify_alignment() -> void:
    var check := model_root.basis * gun_frame_bind
    var residual := check.orthonormalized()
    var error := 0.0
    for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
        error = maxf(error, (residual * axis - axis).length())
    var scale := check.get_scale()
    # Este rig trae el bind algo anisótropo, así que la escala se aplica por eje:
    # se comprueba que sea razonable, no que los tres ejes sean idénticos.
    var spread := maxf(maxf(scale.x, scale.y), scale.z) / maxf(minf(minf(scale.x, scale.y), scale.z), 0.000001)
    # Signos físicos del arma: la mira va por encima de la corredera, el
    # cargador por debajo y detrás. Si alguno falla, el arma quedó girada
    # (pasó: las manos apuntaban hacia abajo, 180 grados).
    var signs_ok := true
    if measured_marks.has("slide") and measured_marks.has("sight") and measured_marks.has("magazine"):
        var slide: Vector3 = measured_marks["slide"]
        var sight: Vector3 = measured_marks["sight"]
        var magazine: Vector3 = measured_marks["magazine"]
        signs_ok = (sight.y - slide.y) > 0.005 and (magazine.y - slide.y) < -0.01 and (magazine.z - slide.z) > 0.005
        if not signs_ok:
            push_error("Orientación del arma incoherente: mira dy=%.4f cargador dy=%.4f dz=%.4f" % [
                sight.y - slide.y, magazine.y - slide.y, magazine.z - slide.z])
    alignment_ok = error <= 0.002 and spread <= 1.5 and signs_ok
    if gun_box.has_volume():
        var centre := gun_box.position + gun_box.size * 0.5
        if absf(centre.x) > 0.004 or absf(centre.z) > 0.004:
            push_error("El arma no está centrada en el frame: centro=%s" % centre)
            alignment_ok = false
    if not alignment_ok:
        push_error("Alineación del Glock incorrecta: residual=%s escala=%s" % [residual, scale])
    if skeleton == null:
        return
    var catch_bone := skeleton.find_bone("SlideCatch")
    if catch_bone >= 0 and (mesh_to_weapon * _bone_origin_in_bind(catch_bone)).x > 0.0:
        alignment_ok = false
        push_warning("La mano del modelo quedó espejada: el cierre de corredera sale a la derecha")


## Origen de un hueso expresado en el espacio de bind de la malla.
func _bone_origin_in_bind(bone: int) -> Vector3:
    return bind_in_skeleton.affine_inverse() * skeleton.get_bone_global_rest(bone).origin


## Transformación local acumulada de `node` hasta su ancestro `ancestor`.
func _local_chain(node: Node, ancestor: Node) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current := node
    while current != null and current != ancestor:
        if current is Node3D:
            result = (current as Node3D).transform * result
        current = current.get_parent()
    return result


## Coloca boca, mira y puerto de expulsión midiendo la geometría ya alineada.
## Cuelgan de un nodo en el frame del arma (metros), no del modelo: así no
## heredan la rotación interna del GLB y sus medidas siguen siendo válidas.
func _build_reference_markers(measure: Dictionary) -> void:
    gun_frame = Node3D.new()
    gun_frame.name = "GunFrame"
    recoil_node.add_child(gun_frame)

    muzzle = Node3D.new()
    muzzle.name = "Muzzle"
    gun_frame.add_child(muzzle)

    sight_marker = Node3D.new()
    sight_marker.name = "SightReference"
    gun_frame.add_child(sight_marker)

    ejection_port = Node3D.new()
    ejection_port.name = "EjectionPort"
    gun_frame.add_child(ejection_port)

    if measure.is_empty():
        # Cotas nominales de una Glock 19 (metros) si la medida falló.
        muzzle.position = Vector3(0.0, 0.015, -0.090)
        sight_marker.position = Vector3(0.0, 0.035, 0.060)
        ejection_port.position = Vector3(0.012, 0.022, 0.010)
        _build_flash()
        return

    # Ojo: los vértices medidos vienen en espacio de MODELO, así que a frame de
    # arma se pasan con la transformación del modelo (no con la de bind).
    var verts: PackedVector3Array = measure["verts"]
    var weapon_verts := PackedVector3Array()
    weapon_verts.resize(verts.size())
    for i in range(verts.size()):
        weapon_verts[i] = model_root.transform * verts[i]
    var box := _bounds(weapon_verts)
    gun_box = box

    # Corona del cañón: centroide de la banda delantera de la malla.
    muzzle.position = _band_centroid(weapon_verts, box, 0.0, 0.04, 0.0, 1.0)
    # Mira trasera: lo más alto de la corredera en la banda trasera.
    sight_marker.position = _band_centroid(weapon_verts, box, 0.80, 1.0, 0.90, 1.0)
    # Puerto de expulsión: cara derecha de la corredera, a media longitud.
    ejection_port.position = _ejection_point(weapon_verts, box)
    # Muñeca: justo detrás de la empuñadura y a la altura del gatillo. El
    # retroceso gira aquí, no sobre el centro del arma.
    wrist_local = Vector3(0.0, box.position.y + box.size.y * 0.55, box.position.z + box.size.z + 0.030)
    print("GLOCK muneca=", wrist_local.snapped(Vector3(0.001, 0.001, 0.001)))
    _build_flash()


## Puerto de expulsión medido: cara derecha (+X) de la corredera entre el 35% y
## el 65% de la longitud, a la altura de la corredera.
func _ejection_point(verts: PackedVector3Array, box: AABB) -> Vector3:
    var z_min := box.position.z + box.size.z * 0.35
    var z_max := box.position.z + box.size.z * 0.65
    var y_min := box.position.y + box.size.y * 0.60
    var face := -INF
    for v in verts:
        if v.z < z_min or v.z > z_max or v.y < y_min:
            continue
        face = maxf(face, v.x)
    if face == -INF:
        return Vector3(0.0, box.position.y + box.size.y * 0.7, box.position.z + box.size.z * 0.5)
    var sum := Vector3.ZERO
    var count := 0
    for v in verts:
        if v.z < z_min or v.z > z_max or v.y < y_min or v.x < face - 0.004:
            continue
        sum += v
        count += 1
    var centre := sum / float(maxi(count, 1))
    # 4 mm dentro de la cara: el casquillo nace en el puerto, no pegado al aire.
    return Vector3(face - 0.004, centre.y, centre.z)


func _bounds(verts: PackedVector3Array) -> AABB:
    if verts.is_empty():
        return AABB()
    var mn := verts[0]
    var mx := verts[0]
    for v in verts:
        mn = mn.min(v)
        mx = mx.max(v)
    return AABB(mn, mx - mn)


## Centroide de los vértices dentro de una banda de la caja: `z0`/`z1` y `y0`/`y1`
## son fracciones de la longitud (boca -> culata) y de la altura (abajo -> arriba).
func _band_centroid(verts: PackedVector3Array, box: AABB, z0: float, z1: float, y0: float, y1: float) -> Vector3:
    var z_min := box.position.z + box.size.z * z0
    var z_max := box.position.z + box.size.z * z1
    var y_min := box.position.y + box.size.y * y0
    var y_max := box.position.y + box.size.y * y1
    var sum := Vector3.ZERO
    var count := 0
    for v in verts:
        if v.z < z_min or v.z > z_max or v.y < y_min or v.y > y_max:
            continue
        sum += v
        count += 1
    if count == 0:
        return sum
    return sum / float(count)


func _build_flash() -> void:
    muzzle_flash = MeshInstance3D.new()
    var flash_quad := QuadMesh.new()
    flash_quad.size = Vector2(0.075, 0.075)
    flash_quad.material = flash_mat
    muzzle_flash.mesh = flash_quad
    muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    muzzle_flash.visible = false
    muzzle.add_child(muzzle_flash)

    muzzle_flash_2 = MeshInstance3D.new()
    var core_quad := QuadMesh.new()
    core_quad.size = Vector2(0.036, 0.036)
    core_quad.material = flash_mat
    muzzle_flash_2.mesh = core_quad
    muzzle_flash_2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    muzzle_flash_2.visible = false
    muzzle.add_child(muzzle_flash_2)

    muzzle_light = OmniLight3D.new()
    muzzle_light.light_color = Color(1.0, 0.78, 0.4)
    muzzle_light.light_energy = 0.0
    muzzle_light.omni_range = 5.5
    muzzle_light.shadow_enabled = false
    muzzle.add_child(muzzle_light)


func _compute_ads_offset() -> void:
    if sight_marker == null or camera == null:
        return
    # Posición del marcador de mira dentro del espacio local del arma (con pose cero).
    sight_marker.force_update_transform()
    force_update_transform()
    camera.force_update_transform()
    var p_rel := global_transform.affine_inverse() * sight_marker.global_position
    # Transformación cámara -> arma (incluye el offset/rotación del WeaponRig).
    var cam_from_glock := camera.global_transform.affine_inverse() * global_transform
    # La mira trasera medida se lleva al centro de la pantalla a distancia real
    # de tiro con pistola (brazo extendido); antes el marcador estaba mal medido
    # y el arma quedaba pegada a la cámara.
    var desired_cam := Vector3(0.0, -ADS_SIGHT_DROP, -ADS_SIGHT_DISTANCE)
    ads_offset = cam_from_glock.affine_inverse() * desired_cam - p_rel


func get_sight_world_position() -> Vector3:
    if sight_marker != null:
        return sight_marker.global_position
    return global_position


func _apply_model_materials() -> void:
    if glock_mesh == null or glock_mesh.mesh == null:
        return
    var materials := GunMaterials.build()
    var missing: Array[String] = []
    for i in range(glock_mesh.mesh.get_surface_count()):
        var surface_name: String = glock_mesh.mesh.surface_get_name(i)
        if materials.has(surface_name):
            glock_mesh.set_surface_override_material(i, materials[surface_name])
        else:
            missing.append(surface_name)
    if not missing.is_empty():
        push_warning("Primitivas del Glock sin material asignado: %s" % ", ".join(missing))
    glock_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _setup_bones() -> void:
    if skeleton == null:
        return
    bone_slide = skeleton.find_bone("Slide")
    bone_trigger = skeleton.find_bone("Trigger")
    bone_magazine = skeleton.find_bone("Magazine")

    if bone_slide >= 0:
        rest_slide = skeleton.get_bone_rest(bone_slide)
    if bone_trigger >= 0:
        rest_trigger = skeleton.get_bone_rest(bone_trigger)
    if bone_magazine >= 0:
        rest_magazine = skeleton.get_bone_rest(bone_magazine)

    _calibrate_bone_units()
    var root_idx := skeleton.find_bone("Root")
    if root_idx >= 0:
        var root_rest := skeleton.get_bone_global_rest(root_idx)
        var inverse_root := root_rest.basis.inverse()
        # Direcciones reales del arma medidas sobre la malla y llevadas al
        # espacio del hueso: la corredera abre hacia atrás y el cargador baja.
        # No se asume que el GLB esté alineado con los ejes de Godot.
        var back_skel := (bind_in_skeleton.basis * gun_frame_bind.z).normalized()
        slide_axis = (inverse_root * back_skel).normalized()


## Cuántas unidades de pose mueven un metro de mundo. No se supone: se mide
## desplazando el hueso de la corredera y viendo cuánto se mueve de verdad.
func _calibrate_bone_units() -> void:
    if skeleton == null or bone_slide < 0:
        return
    skeleton.set_bone_pose_position(bone_slide, rest_slide.origin)
    skeleton.force_update_all_bone_transforms()
    var base := _bone_world_position(bone_slide)
    skeleton.set_bone_pose_position(bone_slide, rest_slide.origin + slide_axis)
    skeleton.force_update_all_bone_transforms()
    var moved := _bone_world_position(bone_slide)
    var metres_per_unit := (moved - base).length()
    skeleton.set_bone_pose_position(bone_slide, rest_slide.origin)
    skeleton.force_update_all_bone_transforms()
    if metres_per_unit > 0.000001:
        bone_units_per_meter = 1.0 / metres_per_unit
        print("GLOCK unidades de pose por metro=", snappedf(bone_units_per_meter, 0.01))


func _bone_world_position(bone: int) -> Vector3:
    return recoil_node.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


func _apply_bone_poses() -> void:
    if skeleton == null:
        return
    if bone_slide >= 0:
        var slide_units := slide_pos * bone_units_per_meter
        skeleton.set_bone_pose_position(bone_slide, rest_slide.origin + slide_axis * slide_units)
    if bone_magazine >= 0:
        # Autoridad del estado: mientras la lógica no da el cargador por
        # asentado, lo mueve la animación del autor (va sincronizada con las
        # manos: sale a 0.40 s y vuelve a 1.10 s). En cuanto está dentro, el
        # juego fuerza la pose de reposo y la animación no puede contradecirlo.
        var animation_drives_mag := reloading and reload_elapsed < RELOAD_MAG_IN_T and animation_player != null
        if not animation_drives_mag:
            skeleton.set_bone_pose_position(bone_magazine, rest_magazine.origin)
            skeleton.set_bone_pose_rotation(bone_magazine, rest_magazine.basis.get_rotation_quaternion())
    if bone_trigger >= 0:
        var angle := -0.30 * trigger_visual
        var trigger_basis := rest_trigger.basis.rotated(Vector3(1, 0, 0), angle)
        skeleton.set_bone_pose_rotation(bone_trigger, trigger_basis.get_rotation_quaternion())
    _apply_pistol_parts()


## ---------------------------------------------------------------------------
## Arma de alta fidelidad (OWK 19) como piezas rígidas.
##
## El asset NO trae esqueleto ni animaciones a propósito, así que no se toca ni
## una línea de la mecánica: `slide_pos`, `trigger_visual`, `reload_elapsed` y
## el resto del estado siguen siendo la única autoridad y aquí sólo se traducen
## a transforms de nodo. Los brazos y sus animaciones siguen siendo del rig
## viejo; lo único que se oculta es su malla de arma.
##
## El modelo se alinea midiendo su geometría, igual que el resto del arma: el
## eje más largo es el cañón y el más corto la anchura, y los signos salen del
## sitio real de la mira (arriba), el cañón (delante) y el cierre de corredera
## (izquierda). No se asume ninguna orientación del exportador.
## ---------------------------------------------------------------------------
const PISTOL_PATH := "res://assets/models/owk19_pistol.glb"
const PISTOL_PARTS := ["Slide", "Frame", "SlideLock", "Barrel", "Sight", "Magazine", "Shell", "Bullet", "Trigger"]

var pistol_root: Node3D
var pistol_parts := {}
var pistol_rest := {}          # transform de reposo de cada pieza, en espacio del modelo
var pistol_scale := 1.0        # metros de arma por unidad del modelo
var pistol_slide_dir := Vector3(0, 0, 1)   # avance de la corredera, en espacio local
var pistol_mag_down := Vector3(0, -1, 0)   # (sin uso; se conserva el nombre por claridad del eje)
var pistol_mag_rest_weapon := Transform3D.IDENTITY  # cargador en reposo, frame del arma
var pistol_grip_local := Vector3.ZERO             # empuñadura medida, frame del arma
var pistol_slide_units := Vector3(0, 0, 1) # metros -> unidades locales de la corredera
var pistol_trigger_axis := Vector3(1, 0, 0)
var pistol_trigger_pivot := Vector3.ZERO
var pistol_ok := false

## Carga la pistola, la mide, la alinea al frame del arma y se la cuelga a
## gun_frame (que ya está en metros). Devuelve true si quedó utilizable.
func _build_high_fidelity_pistol() -> bool:
    var packed := load(PISTOL_PATH) as PackedScene
    if packed == null:
        push_error("No se pudo cargar el arma de alta fidelidad: " + PISTOL_PATH)
        return false
    if gun_frame == null:
        push_error("El arma de alta fidelidad necesita el frame del arma ya construido")
        return false

    var inst := packed.instantiate()
    var holder := Node3D.new()
    holder.name = "PistolOWK19"
    gun_frame.add_child(holder)
    holder.add_child(inst)

    for part_name in PISTOL_PARTS:
        var node := inst.find_child(part_name, true, false) as Node3D
        if node != null:
            pistol_parts[part_name] = node
    for required in ["Slide", "Frame", "Barrel", "Sight", "Trigger", "Magazine"]:
        if not pistol_parts.has(required):
            push_error("Al arma de alta fidelidad le falta la pieza '%s'" % required)
            return false

    # La medida del arma EXCLUYE Shell y Bullet: en este asset son dos objetos
    # sueltos de 2x2x2.3 unidades, mucho mayores que cualquier pieza del arma
    # (~1.6), y colándolos en la caja envolvente falseaban el eje del cañón y la
    # escala (el arma salía gigante y girada 90°). Se miden aparte porque sólo
    # hacen falta para saber si se dibujan, y no se dibujan.
    var skip_names := _subtree_mesh_names(pistol_parts, ["Shell", "Bullet"])
    var gun_verts := PackedVector3Array()
    for part_name in pistol_parts:
        if part_name == "Shell" or part_name == "Bullet":
            continue
        gun_verts.append_array(_part_verts(inst, pistol_parts[part_name], []))
    if gun_verts.is_empty():
        push_error("El arma de alta fidelidad no tiene vértices medibles")
        return false
    var box := _bounds(gun_verts)

    # Eje del cañón = el más largo; altura = el mediano; anchura = el más corto.
    var order := [0, 1, 2]
    order.sort_custom(func(a, b): return box.size[a] > box.size[b])
    var ax_len: int = order[0]
    var ax_h: int = order[1]
    var ax_w: int = order[2]

    var c_sight := _centroid(_part_verts(inst, pistol_parts["Sight"], []))
    var c_barrel := _centroid(_part_verts(inst, pistol_parts["Barrel"], []))
    var c_frame := _centroid(_part_verts(inst, pistol_parts["Frame"], []))
    var c_lock := _centroid(_part_verts(inst, pistol_parts["SlideLock"], [])) if pistol_parts.has("SlideLock") else c_frame

    var unit: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
    # La mira va arriba (+Y) y la boca delante (-Z). El signo de la anchura se
    # elige para que la base sea una rotación propia (determinante +1).
    var s_h := 1.0 if c_sight[ax_h] > c_frame[ax_h] else -1.0
    var s_len := 1.0 if c_barrel[ax_len] > c_frame[ax_len] else -1.0
    var d_len: Vector3 = unit[ax_len] * s_len
    var d_h: Vector3 = unit[ax_h] * s_h
    var d_w: Vector3 = unit[ax_w]
    var w_basis := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
    var rot := w_basis * Basis(d_len, d_h, d_w).transposed()
    if rot.determinant() < 0.0:
        d_w = -d_w
        rot = w_basis * Basis(d_len, d_h, d_w).transposed()

    pistol_scale = GUN_LENGTH / maxf(box.size[ax_len], 0.000001)
    var scaled := rot.scaled(Vector3(pistol_scale, pistol_scale, pistol_scale))
    var framed := _box_in_frame(box, scaled)
    var centre := framed.position + framed.size * 0.5
    holder.transform = Transform3D(scaled, Vector3(
        -centre.x,
        GUN_TOP_OVER_ORIGIN - (framed.position.y + framed.size.y),
        -centre.z))

    # Ejes de la mecánica, traducidos al espacio del modelo.
    # Las piezas se mueven en el espacio LOCAL de su nodo padre, así que la
    # direccion y el pivote hay que expresarlos ahí, no en el del modelo.
    var slide_node := pistol_parts["Slide"] as Node3D
    var trigger_node := pistol_parts["Trigger"] as Node3D
    var mag_node := pistol_parts["Magazine"] as Node3D
    # `transform.origin` vive en el espacio del PADRE de la pieza, así que el
    # vector de un metro hay que expresarlo ahí: padre->inst, luego inst->arma
    # (rot traspuesta) y por último dividir por la escala del arma.
    pistol_slide_units = _meters_in_parent(inst, slide_node, rot, Vector3(0, 0, 1))
    pistol_slide_dir = pistol_slide_units.normalized()
    pistol_mag_down = _meters_in_parent(inst, mag_node, rot, Vector3(0, -1, 0))
    pistol_trigger_axis = _dir_in_parent(inst, trigger_node, rot.transposed() * Vector3(1, 0, 0))
    var trig_pivot_inst := _centroid(_part_verts(inst, trigger_node, []))
    pistol_trigger_pivot = _local_chain(trigger_node, inst).affine_inverse() * trig_pivot_inst

    for part_name in pistol_parts:
        pistol_rest[part_name] = (pistol_parts[part_name] as Node3D).transform
    # Pose de reposo del cargador expresada en el frame del arma (que es el de
    # recoil_node: gun_frame cuelga de el sin transformacion).
    pistol_mag_rest_weapon = (recoil_node as Node3D).global_transform.affine_inverse() * \
        (pistol_parts["Magazine"] as Node3D).global_transform

    # La bala en recámara y la vaina sin expulsar no se dibujan: la munición la
    # lleva la lógica, y el casquillo que sale lo pone el juego.
    for hidden in ["Shell", "Bullet"]:
        if pistol_parts.has(hidden):
            (pistol_parts[hidden] as Node3D).visible = false

    # Empuñadura: vertice mas bajo de la banda trasera del armazon, en el frame
    # del arma. Es donde tiene que caer la mano, no el origen del frame: el arma
    # se centra por su caja envolvente, asi que su empuñadura queda por debajo y
    # por detras del origen.
    var frame_verts := PackedVector3Array()
    for v in _part_verts(inst, pistol_parts["Frame"], []):
        frame_verts.append(holder.transform * v)
    if not frame_verts.is_empty():
        var fb := _bounds(frame_verts)
        var best := Vector3(0.0, 1e9, 0.0)
        var found := false
        for v in frame_verts:
            if v.z < fb.position.z + fb.size.z * 0.55:
                continue
            if not found or v.y < best.y:
                best = v
                found = true
        pistol_grip_local = best if found else Vector3(0.0, fb.position.y, fb.position.z + fb.size.z)
    _apply_pistol_materials(inst)
    _calibrate_viewmodel_lights()
    _rebuild_markers_from_pistol(inst, holder)
    pistol_ok = true
    print("PISTOL_OWK19 piezas=", pistol_parts.size(), " escala=", snappedf(pistol_scale, 0.00001),
        " largo_modelo=", snappedf(box.size[ax_len], 0.0001),
        " caja=", box.size.snapped(Vector3(0.001,0.001,0.001)), " ejes=", [ax_len, ax_h, ax_w],
        " cierre_x=", snappedf(c_lock[ax_w] - c_frame[ax_w], 0.0001))
    return true


## Traduce los materiales PBR del asset al tratamiento del arma.
##
## El GLB importa TODO con metallic = 1.0 y el mapa metallic-roughness dando la
## variacion. En un interior sin reflejos un metal no tiene termino difuso: solo
## puede devolver especular de las dos luces del viewmodel, y por eso el arma
## salia BLANCA y casi recortada en ADS. Es exactamente el mismo problema que ya
## esta documentado en GunMaterials para el arma vieja, y se arregla igual: el
## metal baja a un valor creible para que haya difusa.
##
## NO se toca ninguna textura. El albedo, el normal y la rugosidad se conservan
## enteros: son justamente lo que aporta el asset. Lo unico que se corrige es la
## respuesta del material a la luz que hay en esta escena.
func _apply_pistol_materials(root: Node3D) -> void:
    # Polimero del armazon y cuerpo del cargador: dielectrico, casi sin especular.
    # Corredera, cañon y cierre: acero nitrurado, semimetalico pero no espejo.
    var tuning := {
        "GlockFrame": {"metallic": 0.08},
        "GlockMag": {"metallic": 0.18},
        "GlockSlide": {"metallic": 0.34},
        "Bullet": {"metallic": 0.55},
    }
    var seen := {}
    var stack: Array = [root]
    while not stack.is_empty():
        var node = stack.pop_back()
        if node is MeshInstance3D and node.mesh != null:
            for si in range(node.mesh.get_surface_count()):
                var m: Material = node.get_surface_override_material(si)
                if m == null:
                    m = node.mesh.surface_get_material(si)
                if not (m is StandardMaterial3D):
                    continue
                var sm := m as StandardMaterial3D
                var key := sm.resource_name
                if tuning.has(key) and not seen.has(key):
                    seen[key] = true
                    var t: Dictionary = tuning[key]
                    sm.metallic = float(t["metallic"])
                    # OJO: en Godot la rugosidad final es `roughness` MULTIPLICADO por el
                    # canal de la textura, no un minimo. Poner 0.32 para "subir el
                    # suelo" en realidad BAJABA la rugosidad, dejaba el arma mas pulida
                    # y peor: salia mas quemada. Se deja en 1.0 para que la textura
                    # mande tal cual y el unico cambio sea el metallic.
                    sm.roughness = 1.0
                    sm.metallic_specular = 0.35
                # El asset viene doubleSided en las 4 familias. Es geometria
                # cerrada: dibujar tambien las caras de atras duplica el trabajo
                # de fragmento y ensucia el sombreado.
                sm.cull_mode = BaseMaterial3D.CULL_BACK
        for child in node.get_children():
            stack.append(child)
    print("PISTOL_MATERIALES tocados=", seen.keys())


## ---------------------------------------------------------------------------
## Brazos del rig de Cransh.
##
## Este rig trae las animaciones CON los brazos, asi que no hay retargeting: se
## sustituye el conjunto entero. Se alinea anclando su hueso de camara
## (`Head_Cam_014`) a la camara del juego, que es un punto que el propio autor
## puso donde va el ojo: en vez de suponer escala y orientacion, se mide.
##
## Solo se usa la malla de brazos. El GLB trae ademas una pistola propia
## (`xd_frame`, 17 818 tris) que no se dibuja porque el arma de FlowFire es la
## OWK 19.
## ---------------------------------------------------------------------------
const ARMS_PATH := "res://assets/models/fps_pistol_arms.glb"

var arms_root: Node3D
var arms_skeleton: Skeleton3D
var arms_player: AnimationPlayer
var arms_ok := false

func _install_arms() -> void:
    # OPT-IN con --newarms. El montaje esta a medio resolver: el anclaje por el
    # hueso de camara coloca bien el punto de vista, pero los brazos todavia no
    # encuadran (queda uno suelto y sobredimensionado y el arma flota). Hasta que
    # eso se cierre, el juego usa los brazos del rig viejo, que funcionan.
    if not OS.get_cmdline_user_args().has("--newarms"):
        return
    var packed := load(ARMS_PATH) as PackedScene
    if packed == null:
        push_warning("No se pudieron cargar los brazos nuevos: " + ARMS_PATH)
        return
    arms_root = packed.instantiate()
    arms_root.name = "ArmsCransh"
    arms_skeleton = arms_root.find_child("Skeleton3D", true, false) as Skeleton3D
    arms_player = arms_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
    if arms_skeleton == null or camera == null:
        push_warning("Los brazos nuevos no traen esqueleto utilizable")
        arms_root.queue_free()
        arms_root = null
        return
    # La raiz del GLB trae su propia escala/rotacion de Sketchfab. NO se puede
    # sobrescribir su transform: hay que meterla bajo un envoltorio y mover el
    # envoltorio. Sin esto las proporciones se pierden y los brazos salen
    # gigantes (medido: se comian media pantalla).
    var holder := Node3D.new()
    holder.name = "ArmsMount"
    recoil_node.add_child(holder)
    holder.add_child(arms_root)

    # Fuera la pistola que trae el asset: el arma es la OWK 19. Los nombres que
    # Ocultar la pistola que trae el asset. NO se puede filtrar por nombre: el
    # importador renombra las mallas a Object_N y el filtro por "xd_frame" no
    # casaba con ninguna, asi que la pistola del autor se seguia dibujando
    # encima de la OWK 19. Se identifica la malla de brazos por ser la que mas
    # vertices tiene (14 852 tris frente a 8 139, 4 697 y 4 982) y se oculta el
    # resto: asi el criterio no depende de como nombre el importador.
    var mallas: Array = []
    var stack: Array = [arms_root]
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and n.mesh != null:
            mallas.append(n)
        for c in n.get_children():
            stack.append(c)
    var brazos: MeshInstance3D = null
    var mayor := -1
    for m in mallas:
        var verts := 0
        for si in range((m as MeshInstance3D).mesh.get_surface_count()):
            verts += ((m as MeshInstance3D).mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        if verts > mayor:
            mayor = verts
            brazos = m
    var ocultas := 0
    for m in mallas:
        if m != brazos:
            (m as MeshInstance3D).visible = false
            ocultas += 1
    print("ARMS_MALLAS total=", mallas.size(), " brazos=", (brazos.name if brazos != null else "?"),
        " vertices_brazos=", mayor, " ocultas=", ocultas)

    # Anclaje por el hueso del ARMA (`Rif_059`), no por el de camara: el arma es
    # el punto cuya posicion fija la mecanica de FlowFire, y las manos vienen a
    # ella por la animacion, no al reves. Ver el aviso de arriba sobre por que
    # `Head_Cam_014` no vale.
    var rif_bone := -1
    for b in range(arms_skeleton.get_bone_count()):
        if arms_skeleton.get_bone_name(b).begins_with("Rif"):
            rif_bone = b
            break
    if rif_bone < 0 or gun_frame == null:
        push_warning("Los brazos nuevos no traen hueso de arma: no se pueden anclar")
        holder.queue_free()
        arms_root = null
        return
    # La orientacion se corrige con el giro de 90 sobre X ya validado (la caja
    # pasa a 0.664 x 0.323 x 0.678, la forma de unos brazos extendidos) y se
    # toma la del frame del arma como referencia, no la base del hueso: una base
    # de hueso de Blender apunta a lo largo del hueso, no segun los ejes.
    # Dos correcciones de orientacion, ambas medidas:
    #  - 90 grados sobre X: el rig trae Y y Z intercambiados (el largo del brazo
    #    caia en vertical);
    #  - 180 grados sobre el eje de vision: con solo lo anterior los codos
    #    salian por ARRIBA en vez de por abajo.
    var fix := Basis(Vector3.BACK, PI) * Basis(Vector3.RIGHT, PI * 0.5)
    var rif_rest: Transform3D = arms_skeleton.get_bone_global_rest(rif_bone)
    # ESCALA: las manos del rig estan modeladas alrededor de la pistola del autor
    # (`xd_frame`), que mide 42 x 180 x 206 mm; la OWK 19 mide 34 x 130 x 186, o
    # sea 1.38x mas baja. Por eso el guante envolvia la pistola entera. Se escala
    # el conjunto de brazos a la pistola REAL en vez de agrandar el arma, que ya
    # esta verificada contra las cotas de una Glock 19 (33 x 127 x 186 reales).
    var escala_manos := 130.0 / 180.0
    holder.global_transform = (gun_frame as Node3D).global_transform * Transform3D(fix.scaled(Vector3(escala_manos, escala_manos, escala_manos)), Vector3.ZERO)
    force_update_transform()
    arms_skeleton.force_update_transform()
    # Se alinea el punto de agarre del rig (media de las dos manos) con la
    # EMPUÑADURA medida de la OWK, no con el origen del frame: alinear el hueso
    # del arma con el origen dejaba la mano desplazada, porque la empuñadura de
    # la OWK cae por debajo y por detras de ese origen.
    var hl := -1
    var hr := -1
    for b in range(arms_skeleton.get_bone_count()):
        var bn := arms_skeleton.get_bone_name(b)
        if bn.begins_with("Hand_L"):
            hl = b
        elif bn.begins_with("Hand_R"):
            hr = b
    if hl < 0 or hr < 0:
        push_warning("Los brazos nuevos no traen huesos de mano")
        holder.queue_free()
        arms_root = null
        return
    var mano_l: Vector3 = (arms_skeleton.global_transform * arms_skeleton.get_bone_global_rest(hl)).origin
    var mano_r: Vector3 = (arms_skeleton.global_transform * arms_skeleton.get_bone_global_rest(hr)).origin
    var agarre: Vector3 = mano_l.lerp(mano_r, 0.5)
    var empunadura: Vector3 = (gun_frame as Node3D).global_transform * pistol_grip_local
    holder.global_transform.origin += empunadura - agarre

    if arms_mesh != null:
        arms_mesh.visible = false
    arms_ok = true
    print("ARMS_CRANSH ok anclado_al_arma anim=", arms_player.get_animation_list() if arms_player != null else [])


## Vuelve a medir boca, mira y puerto de expulsion sobre el arma NUEVA.
##
## Los marcadores los calcula _build_reference_markers a partir de los vertices
## del rig VIEJO, asi que al cambiar de arma seguian diciendo donde estaba la
## mira de la Glock low-poly. `aimtest` pasaba igual, porque comprueba el
## marcador contra el centro de la camara, no la mira que se ve: con el arma
## nueva se podia estar apuntando con una mira que no era donde cae la bala.
##
## Se reutilizan los mismos ayudantes (_band_centroid, _ejection_point) sobre la
## geometria nueva, en el frame del arma, para que la regla sea exactamente la
## misma que con el arma vieja.
func _rebuild_markers_from_pistol(inst: Node3D, holder: Node3D) -> void:
    if muzzle == null or sight_marker == null or ejection_port == null:
        return
    var weapon_verts := PackedVector3Array()
    for part_name in pistol_parts:
        if part_name == "Shell" or part_name == "Bullet":
            continue
        for v in _part_verts(inst, pistol_parts[part_name], []):
            weapon_verts.append(holder.transform * v)
    if weapon_verts.is_empty():
        push_error("No se pudo medir el arma nueva para recolocar los marcadores")
        return
    gun_box = _bounds(weapon_verts)
    muzzle.position = _band_centroid(weapon_verts, gun_box, 0.0, 0.04, 0.0, 1.0)
    sight_marker.position = _band_centroid(weapon_verts, gun_box, 0.80, 1.0, 0.90, 1.0)
    ejection_port.position = _ejection_point(weapon_verts, gun_box)
    wrist_local = Vector3(0.0, gun_box.position.y + gun_box.size.y * 0.55,
        gun_box.position.z + gun_box.size.z + 0.030)
    _compute_ads_offset()
    print("PISTOL_MARCADORES mira=", sight_marker.position.snapped(Vector3(0.001,0.001,0.001)),
        " boca=", muzzle.position.snapped(Vector3(0.001,0.001,0.001)),
        " caja=", gun_box.size.snapped(Vector3(0.001,0.001,0.001)),
        " ads_offset=", ads_offset.snapped(Vector3(0.001,0.001,0.001)))


## Recalibra las dos luces del viewmodel para el arma nueva.
##
## Las luces se ajustaron en su dia para el arma vieja, cuyo albedo es casi
## negro (~0.05 lineal): con esa albedo hacian falta 2.9 de energia para que el
## arma se leyera. El asset nuevo trae albedo PBR de verdad (~0.12 tipico y
## hasta 0.5 en las zonas claras), asi que la misma luz lo quema: medido, 4-10%
## de los pixeles del arma recortados a blanco, contra 0.1-1.2% del arma vieja,
## y en pantalla se veia una mancha blanca en ADS.
##
## El problema no era el material del asset, era la luz que heredaba. Se baja
## solo cuando el arma nueva esta activa, para que la vieja siga comparable.
func _calibrate_viewmodel_lights() -> void:
    if viewmodel_light != null:
        viewmodel_light.light_energy = 0.85
    for child in pose_root.get_children():
        if child is OmniLight3D and child != viewmodel_light:
            (child as OmniLight3D).light_energy = 0.30
    print("PISTOL_LUCES key=", viewmodel_light.light_energy if viewmodel_light != null else -1.0)


## Vértices de una pieza expresados en el espacio de `reference` (el nodo que se
## cuelga del arma). Medir en el espacio de la propia pieza NO vale: se deja
## fuera la rotación del nodo raíz del GLB, que sí se aplica al dibujar, y el
## arma sale girada 90°.
func _part_verts(reference: Node3D, part: Node3D, skip: Array) -> PackedVector3Array:
    var out := PackedVector3Array()
    var part_in_ref: Transform3D = _local_chain(part, reference)
    var stack: Array = [part]
    while not stack.is_empty():
        var node = stack.pop_back()
        if node is MeshInstance3D and node.mesh != null and not skip.has(node.name):
            var xf: Transform3D = part_in_ref * _local_chain(node, part)
            for i in range(node.mesh.get_surface_count()):
                for v in node.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
                    out.append(xf * v)
        for child in node.get_children():
            stack.append(child)
    return out


## Nombres de las mallas dentro de las piezas indicadas, para poder excluirlas.
func _subtree_mesh_names(parts: Dictionary, part_names: Array) -> Array:
    var names: Array = []
    for part_name in part_names:
        if not parts.has(part_name):
            continue
        var stack: Array = [parts[part_name]]
        while not stack.is_empty():
            var node = stack.pop_back()
            if node is MeshInstance3D:
                names.append(node.name)
            for child in node.get_children():
                stack.append(child)
    return names


## Vector, en unidades del padre de `node`, que corresponde a UN METRO del arma
## en la dirección `weapon_dir` (medida en el frame del arma).
func _meters_in_parent(reference: Node3D, node: Node3D, rot: Basis, weapon_dir: Vector3) -> Vector3:
    var parent_in_ref: Transform3D = _local_chain(node.get_parent(), reference)
    return parent_in_ref.basis.inverse() * (rot.transposed() * weapon_dir) / pistol_scale


## Dirección de `dir_in_ref` expresada en el espacio local del padre de `node`.
func _dir_in_parent(reference: Node3D, node: Node3D, dir_in_ref: Vector3) -> Vector3:
    var parent_in_ref: Transform3D = _local_chain(node.get_parent(), reference)
    return (parent_in_ref.basis.inverse() * dir_in_ref).normalized()


## Vértices de todas las mallas bajo `root`, expresados en el espacio de `root`.
func _collect_rigid_verts(root: Node3D, skip: Array) -> PackedVector3Array:
    var out := PackedVector3Array()
    var stack: Array = [root]
    while not stack.is_empty():
        var node = stack.pop_back()
        if node is MeshInstance3D and node.mesh != null and not skip.has(node.name):
            var xf: Transform3D = _local_chain(node, root)
            for i in range(node.mesh.get_surface_count()):
                for v in node.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
                    out.append(xf * v)
        for child in node.get_children():
            stack.append(child)
    return out


## Traduce el estado mecánico (que no cambia) a transforms de las piezas.
func _apply_pistol_parts() -> void:
    if not pistol_ok:
        return
    var slide := pistol_parts["Slide"] as Node3D
    slide.transform.origin = (pistol_rest["Slide"] as Transform3D).origin + pistol_slide_units * slide_pos

    var trigger := pistol_parts["Trigger"] as Node3D
    var trig := Basis(pistol_trigger_axis, -0.30 * trigger_visual)
    trigger.transform = Transform3D(trig, pistol_trigger_pivot - trig * pistol_trigger_pivot)

    # Cargador: la lógica manda. Sale del brocal a los 0.40 s y vuelve a los
    # 1.10 s, los mismos instantes que usa la animación del autor para las
    # manos, así que el gesto y el objeto coinciden en el tiempo.
    # El cargador lo mueve el hueso Magazine del rig viejo, no una aproximacion
    # por tiempos. Ese hueso ya esta animado por el autor en sincronia con las
    # manos, y _apply_bone_poses lo devuelve a reposo en cuanto la logica da el
    # cargador por asentado, asi que la animacion y la mecanica siguen siendo
    # las mismas que con el arma vieja: lo unico que cambia es que ahora arrastra
    # la malla del cargador nuevo.
    #
    # Se reutiliza la conjugacion que ya usaba _mag_screen_box en DevTools: el
    # hueso y el arma no comparten ejes, asi que la pose relativa del hueso hay
    # que llevarla al frame del arma antes de aplicarla.
    var mag := pistol_parts["Magazine"] as Node3D
    if bone_magazine < 0 or skeleton == null or recoil_node == null:
        mag.transform = pistol_rest["Magazine"] as Transform3D
        return
    var skel_from_weapon: Transform3D = ((model_root as Node3D).transform *
        _local_chain(skeleton, model_root)).affine_inverse()
    var weapon_from_skel: Transform3D = skel_from_weapon.affine_inverse()
    var rel_skel: Transform3D = skeleton.get_bone_global_pose(bone_magazine) * skeleton.get_bone_global_rest(bone_magazine).affine_inverse()
    var rel_weapon: Transform3D = weapon_from_skel * rel_skel * skel_from_weapon
    mag.global_transform = (recoil_node as Node3D).global_transform * (rel_weapon * pistol_mag_rest_weapon)
