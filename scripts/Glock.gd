extends Node3D

signal shot_fired
signal ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool)

## Viewmodel de FlowFire: una sola Glock (OWK 19) sobre unos solos brazos (Cransh).
##
## Cadena en runtime:
##   Camera -> WeaponRig -> Glock(logica) -> PoseRoot -> RecoilNode -> ArmsMount
##     -> ArmsRoot(Cransh) -> Skeleton3D -> PBody/Pmag (huesos) -> OWK 19
##
## Autoridades: la LOGICA (municion, corredera, gatillo, cadencia, recarga) manda
## el estado; las MANOS (animaciones del autor: Idle/Fire/Reload) mandan la pose
## humana y arrastran el arma (cuerpo via PBody, cargador via Pmag); la OWK 19 es
## la UNICA malla de arma visible; la MIRA visible (alza real) define el ADS.
const MAG_SIZE := 17
const GUN_LENGTH := 0.186  # Glock 19 real: 186 mm de punta a punta.
const ADS_SIGHT_DISTANCE := 0.42  # Ojo -> mira trasera con el brazo extendido.
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
# Tiempos de la animación "Reload" del autor (medidos sobre sus claves): el
# cargador sale a los 0.40 s, vuelve a su sitio a los 1.10 s y la corredera se
# libera a los 1.70 s. La lógica usa esos mismos instantes, así que las manos
# y la mecánica no pueden contradecirse.
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
var flash_mat: ShaderMaterial
var flash_core_mat: ShaderMaterial

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

var sight_marker: Node3D
var front_marker: Node3D
var ads_offset := Vector3(0.0, 0.15, -0.24)  # pose de ADS: la resuelve _solve_ads()
var ads_rot := Vector3.ZERO  # giro de ADS resuelto junto al offset (radianes)
# Caja real del arma en el marco del arma (metros, medida sobre la OWK).
var gun_box := AABB()
# Escala uniforme del conjunto de brazos (manos a la empuñadura real).
# Derivada en runtime (altura empuñadura OWK / altura empuñadura del autor):
# las manos del autor envuelven una pistola mayor y sin esto tragaban la OWK.
var arms_scale := 1.0
var trigger_visual := 0.0


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
    _build_viewmodel()
    _install_arms()
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
    # El ADS se resuelve contra la mira visible una vez hay camara.
    _solve_ads()


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
    # `_play_reload_animation()` resuelve una sola vez la animación que
    # corresponde al estado mecánico. Antes se llamaba también a
    # `_play_arms_anim()` en el mismo frame y el clip se reiniciaba dos veces.
    _play_reload_animation()
    _emit_ammo()
    return true


## Arranca la animación de recarga del autor sin encolar el idle: el final lo
## decide la lógica (corte táctico o mezcla al terminar).
func _play_reload_animation() -> void:
    _play_arms_anim("FPS_Pistol_Reload_full" if reload_empty else "FPS_Pistol_Reload_easy")


func _blend_to_idle(blend: float) -> void:
    if arms_player == null:
        return
    var idle := _resolve_arms_idle()
    if idle != "":
        arms_player.play(idle, blend)


func _can_fire() -> bool:
    return not reloading and chamber > 0 and absf(slide_pos) < 0.0025


func _process(delta: float) -> void:
    _update_trigger(delta)
    _update_slide(delta)
    _update_recoil(delta)
    _update_reload(delta)
    _update_pose(delta)
    _apply_pistol_parts()

    muzzle_timer = maxf(0.0, muzzle_timer - delta)
    shot_pulse = maxf(0.0, shot_pulse - delta * 8.0)

    var flash_visible := muzzle_timer > 0.0
    if flash_visible and camera != null:
        # Los quads se orientan desde la autoridad de cámara. `billboard` no es
        # un render mode válido para shaders espaciales de Godot 4.
        muzzle_flash.look_at(camera.global_position, Vector3.UP)
        muzzle_flash_2.look_at(camera.global_position, Vector3.UP)
    if muzzle_flash != null:
        muzzle_flash.visible = flash_visible
    if muzzle_flash_2 != null:
        muzzle_flash_2.visible = flash_visible
    if muzzle_light != null:
        # Pulso corto sobre el entorno, no una segunda fuente de iluminación
        # amarilla que convierta tela y piel en metal dorado.
        muzzle_light.light_energy = randf_range(0.65, 1.10) if flash_visible else 0.0


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

    # 2) arma en la mano: la animacion Fire del autor ya aporta el latigazo
    # grueso (medido: 24 grados y 5 cm en 0.23 s). La capa procedural solo
    # añade el punch rapido sobre el mismo conjunto (brazos+arma juntos, ya que
    # el arma cuelga de la mano): se deja a ~1/3 de su valor anterior para no
    # duplicar el gesto.
    recoil_vel += Vector3((randf() - 0.5) * 0.02, 0.035, 0.22 + randf() * 0.02)
    recoil_rot_vel += Vector3(1.6 + randf() * 0.25, (randf() - 0.5) * 0.2, (randf() - 0.5) * 0.3)
    # 3) brazos: el mismo disparo, pero el hombro absorbe en otra escala (k=90).
    arm_recoil_vel += Vector3((randf() - 0.5) * 0.03, 0.05, 0.20 + randf() * 0.03)
    arm_recoil_rot_vel += Vector3(0.47 + randf() * 0.12, 0.0, (randf() - 0.5) * 0.16)

    muzzle_timer = 0.04
    muzzle_flash.rotation.z = randf_range(0.0, TAU)
    muzzle_flash.scale = Vector3.ONE * randf_range(0.85, 1.35)
    muzzle_flash_2.rotation.z = randf_range(0.0, TAU)
    muzzle_flash_2.scale = Vector3.ONE * randf_range(0.7, 1.2)

    GameAudio.play_shot()
    _play_arms_anim("FPS_Pistol_Fire")

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
    var ads_pose_rot := ads_rot
    var sprint_rot := Vector3(deg_to_rad(-14.0), deg_to_rad(-5.0), deg_to_rad(5.0))

    var carry_pos := hip_pos.lerp(sprint_pos, sprint_blend)
    var carry_rot := hip_rot.lerp(sprint_rot, sprint_blend)
    var pos := carry_pos.lerp(ads_pos, aim_blend)
    var rot := carry_rot.lerp(ads_pose_rot, aim_blend)

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
    # El tope tiene que dejar pasar la pose de ADS: la pistola sube desde la
    # postura baja de descanso hasta la mira sin quedar recortada.
    # El limite sigue existiendo para el balanceo, el bob y el retroceso, que son
    # los que podian desmadrar el arma.
    pos.x = clampf(pos.x, -0.30, 0.30)
    pos.y = clampf(pos.y, -0.30, maxf(0.18, ads_pos.y))
    pos.z = clampf(pos.z, minf(-0.20, ads_pos.z), 0.15)
    # El límite del balanceo no debe recortar una inclinación ADS elegida por
    # captura: la pose de apuntado puede necesitar más de 20° para que el cañón
    # quede apenas por debajo del frente, mientras hip y el retroceso conservan
    # el límite corto.
    var rot_limit := maxf(0.35, absf(ads_pose_rot.x) + 0.015)
    rot.x = clampf(rot.x, -rot_limit, rot_limit)
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
    # Solo el laton de los casquillos y el material del fogonazo. El arma
    # (OWK) y los brazos (Cransh) usan sus materiales PBR de origen.
    # Latón pulido: albedo de metal real y sin emisión (una vaina caliente no
    # brilla; la hacía visible el brillo del entorno, no un truco).
    brass_mat = StandardMaterial3D.new()
    brass_mat.albedo_color = Color(0.86, 0.68, 0.30)
    brass_mat.metallic = 0.95
    brass_mat.roughness = 0.24

    # El sprite anterior era una estrella radial perfecta. Este shader mínimo
    # conserva la economía de un quad, pero da un núcleo irregular y dos
    # lenguas orientadas: no parece un decal pegado a la boca del arma.
    var flash_shader := Shader.new()
    flash_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 flash_color : source_color = vec4(1.0, 0.68, 0.22, 1.0);
uniform float intensity = 1.0;

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float core = exp(-dot(p * vec2(1.0, 1.35), p * vec2(1.0, 1.35)) * 8.0);
    vec2 tongue_a = p - vec2(-0.12, 0.25);
    vec2 tongue_b = p - vec2(0.18, -0.16);
    float lobe_a = exp(-dot(tongue_a * vec2(5.2, 2.2), tongue_a * vec2(5.2, 2.2)) * 1.4);
    float lobe_b = exp(-dot(tongue_b * vec2(4.0, 2.8), tongue_b * vec2(4.0, 2.8)) * 1.5);
    float edge = 1.0 - smoothstep(0.72, 1.0, length(p));
    float shape = max(core, max(lobe_a * 0.72, lobe_b * 0.58)) * edge;
    ALBEDO = flash_color.rgb;
    EMISSION = flash_color.rgb * intensity;
    ALPHA = clamp(shape, 0.0, 1.0);
}
"""
    flash_mat = ShaderMaterial.new()
    flash_mat.shader = flash_shader
    flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.58, 0.16, 1.0))
    flash_mat.set_shader_parameter("intensity", 1.8)
    flash_core_mat = flash_mat.duplicate() as ShaderMaterial
    flash_core_mat.set_shader_parameter("flash_color", Color(1.0, 0.88, 0.52, 1.0))
    flash_core_mat.set_shader_parameter("intensity", 1.35)


## Construye el viewmodel: la OWK 19 como UNICA arma. Sin rig legacy, sin
## mallas ocultas, sin esqueletos de soporte: piezas rigidas medidas sobre su
## propia geometria, movidas por la logica (corredera/gatillo) y por las manos
## (cuerpo via PBody, cargador via Pmag; ver _install_arms).
func _build_viewmodel() -> void:
    if not _build_high_fidelity_pistol():
        push_error("No se pudo construir la OWK 19: sin arma no hay viewmodel")
        return
    print("GLOCK arma=owk19 unica")


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


## Transformación local acumulada de `node` hasta su ancestro `ancestor`.
func _local_chain(node: Node, ancestor: Node) -> Transform3D:
    var result := Transform3D.IDENTITY
    var current := node
    while current != null and current != ancestor:
        if current is Node3D:
            result = (current as Node3D).transform * result
        current = current.get_parent()
    return result


## Centroide de una lista de puntos.
func _centroid(points: PackedVector3Array) -> Vector3:
    var sum := Vector3.ZERO
    for p in points:
        sum += p
    return sum / float(maxi(points.size(), 1))


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
    flash_quad.size = Vector2(0.064, 0.050)
    flash_quad.material = flash_mat
    muzzle_flash.mesh = flash_quad
    muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    muzzle_flash.visible = false
    muzzle.add_child(muzzle_flash)

    muzzle_flash_2 = MeshInstance3D.new()
    var core_quad := QuadMesh.new()
    core_quad.size = Vector2(0.030, 0.026)
    core_quad.material = flash_core_mat
    muzzle_flash_2.mesh = core_quad
    muzzle_flash_2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    muzzle_flash_2.visible = false
    muzzle.add_child(muzzle_flash_2)

    muzzle_light = OmniLight3D.new()
    muzzle_light.light_color = Color(1.0, 0.86, 0.70)
    muzzle_light.light_energy = 0.0
    muzzle_light.omni_range = 2.4
    muzzle_light.shadow_enabled = false
    muzzle.add_child(muzzle_light)


## Resuelve la pose de ADS desde la mira visible real (alza trasera y
## delantera de la OWK). Sin capturas, sin prueba-error, sin circularidad:
## la linea de mira (trasera->delantera) se lleva al eje optico de la camara y
## el alza trasera a la distancia de tiro con brazo extendido. Los marcadores
## son la FUENTE (geometria fija); la pose es la DERIVADA; el test comprueba el
## PRODUCTO (proyeccion en pantalla). Mover cualquiera de los tres rompe el
## test, que es exactamente lo que debe vigilar.
func _solve_ads() -> void:
    if sight_marker == null or front_marker == null or camera == null:
        return
    (sight_marker as Node3D).force_update_transform()
    (front_marker as Node3D).force_update_transform()
    (pose_root as Node3D).force_update_transform()
    (self as Node3D).force_update_transform()
    camera.force_update_transform()
    # Todo en espacio de Glock: el WeaponRig cuelga de la camara, asi que la
    # pose resuelta aqui acompaña a la respiracion y al bob sin perder el cero.
    var glock_inv: Transform3D = (self as Node3D).global_transform.affine_inverse()
    var rear_g: Vector3 = glock_inv * (sight_marker as Node3D).global_position
    var front_g: Vector3 = glock_inv * (front_marker as Node3D).global_position
    var eye_g: Vector3 = glock_inv * camera.global_position
    var axis_g: Vector3 = (glock_inv.basis * -camera.global_transform.basis.z).normalized()
    var sight_dir: Vector3 = (front_g - rear_g).normalized()
    # Rotacion minima que lleva la linea de mira al eje, mas correccion de
    # balanceo para que el arma quede vertical (sin canto).
    var rot := Basis.IDENTITY
    var cross := sight_dir.cross(axis_g)
    if cross.length() > 0.00001 and absf(sight_dir.dot(axis_g)) < 0.99999:
        rot = Basis(cross.normalized(), sight_dir.angle_to(axis_g)) * rot
    var up_after: Vector3 = (rot * Vector3.UP).normalized()
    var up_proj: Vector3 = Vector3.UP - axis_g * Vector3.UP.dot(axis_g)
    if up_proj.length() > 0.001 and up_after.length() > 0.001:
        up_proj = up_proj.normalized()
        var roll_axis: Vector3 = axis_g
        var a := atan2(up_after.cross(up_proj).dot(roll_axis), up_after.dot(up_proj))
        rot = Basis(roll_axis, a) * rot
    var target_rear: Vector3 = eye_g + axis_g * ADS_SIGHT_DISTANCE
    # La pose rota sobre el origen de pose_root: primero rota el alza, luego se
    # traslada hasta su punto. Exacto para cadenas rigidas, sin iterar.
    var origin_g: Vector3 = glock_inv * (pose_root as Node3D).global_position
    var rear_rotated: Vector3 = origin_g + (rot * (rear_g - origin_g))
    ads_offset = target_rear - rear_rotated
    ads_rot = rot.get_euler()
    print("ADS_GEOMETRICO offset=", ads_offset.snapped(Vector3(0.001, 0.001, 0.001)),
        " rot_deg=", (ads_rot * 180.0 / PI).snapped(Vector3(0.1, 0.1, 0.1)),
        " linea_mira=", sight_dir.snapped(Vector3(0.001, 0.001, 0.001)))


func get_sight_world_position() -> Vector3:
    if sight_marker != null:
        return sight_marker.global_position
    return global_position


func get_front_sight_world_position() -> Vector3:
    if front_marker != null:
        return front_marker.global_position
    return get_sight_world_position()
## ---------------------------------------------------------------------------
## OWK 19 como piezas rigidas: la UNICA arma del juego.
##
## El asset NO trae esqueleto ni animaciones a proposito: `slide_pos`,
## `trigger_visual` y el resto del estado logico son la unica autoridad y aqui
## solo se traducen a transforms de nodo. El cuerpo cuelga del hueso PBody del
## autor (la mano que empuña) y el cargador del hueso Pmag (el que lo extrae):
## ver _install_arms. Corredera y gatillo los mueve la logica; el cargador lo
## arrastra la animacion de recarga del autor, en fase con las manos por
## construccion.
##
## El modelo se alinea midiendo su geometria: el eje mas largo es el cañon y el
## mas corto la anchura, y los signos salen del sitio real de la mira (arriba),
## el cañon (delante) y el cierre de corredera (izquierda).
## ---------------------------------------------------------------------------
const PISTOL_PATH := "res://assets/models/owk19_pistol.glb"
const PISTOL_PARTS := ["Slide", "Frame", "SlideLock", "Barrel", "Sight", "Magazine", "Shell", "Bullet", "Trigger"]

var pistol_holder: Node3D  # cuerpo del arma (todo menos el cargador), bajo PBody
var pistol_mag_node: Node3D  # cargador visible, bajo Pmag
var pistol_parts := {}
var pistol_rest := {}          # transform de reposo de cada pieza, en su espacio local
var pistol_scale := 1.0        # metros de arma por unidad del modelo
var pistol_slide_dir := Vector3(0, 0, 1)   # avance de la corredera, en espacio local
var pistol_grip_local := Vector3.ZERO             # empuñadura medida, frame del arma
var pistol_slide_units := Vector3(0, 0, 1) # metros -> unidades locales de la corredera
var pistol_trigger_axis := Vector3(1, 0, 0)
var pistol_trigger_pivot := Vector3.ZERO
var pistol_ok := false

## Carga la pistola, la mide y la alinea al marco del arma (metros).
## El cuerpo queda en un soporte provisional bajo recoil_node; _install_arms lo
## cuelga del hueso PBody y el cargador del hueso Pmag. Devuelve true si usable.
func _build_high_fidelity_pistol() -> bool:
    var packed := load(PISTOL_PATH) as PackedScene
    if packed == null:
        push_error("No se pudo cargar el arma de alta fidelidad: " + PISTOL_PATH)
        return false

    var inst := packed.instantiate()
    inst.name = "OWK19Model"
    # El holder es el MARCO DEL ARMA en metros (identidad): los marcadores
    # cuelgan de el con cotas en metros. La alineacion modelo->metros va en la
    # raiz del GLB, no en el holder: si el holder llevara la escala del modelo
    # (0.099), encogeria tambien a sus hijos (miras, boca) 10 veces.
    var holder := Node3D.new()
    holder.name = "PistolOWK19"
    recoil_node.add_child(holder)
    holder.add_child(inst)
    pistol_holder = holder

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
    inst.transform = Transform3D(scaled, Vector3(
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
    pistol_trigger_axis = _dir_in_parent(inst, trigger_node, rot.transposed() * Vector3(1, 0, 0))
    var trig_pivot_inst := _centroid(_part_verts(inst, trigger_node, []))
    pistol_trigger_pivot = _local_chain(trigger_node, inst).affine_inverse() * trig_pivot_inst

    for part_name in pistol_parts:
        pistol_rest[part_name] = (pistol_parts[part_name] as Node3D).transform
    pistol_mag_node = mag_node

    # La bala en recámara y la vaina sin expulsar no se dibujan: la munición la
    # lleva la lógica, y el casquillo que sale lo pone el juego.
    for hidden in ["Shell", "Bullet"]:
        if pistol_parts.has(hidden):
            (pistol_parts[hidden] as Node3D).visible = false

    # Empuñadura: vertice mas bajo de la banda trasera del armazon, en el frame
    # del arma. Es donde tiene que caer la mano, no el origen del frame: el arma
    # se centra por su caja envolvente, asi que su empuñadura queda por debajo y
    # por detras del origen.
    # _part_verts en espacio del holder YA es marco del arma (la alineacion vive
    # en la raiz del GLB, bajo el holder): sin multiplicar de mas.
    var frame_verts := PackedVector3Array()
    frame_verts.append_array(_part_verts(holder, pistol_parts["Frame"], []))
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
## salia BLANCA y casi recortada en ADS. El metal baja a un valor creible para
## que haya difusa.
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
## Brazos de Cransh: la pose humana.
##
## El rig trae animaciones CON los brazos (Idle/Fire/Reload x2): no hay
## retargeting ni IK. El conjunto se coloca UNA vez con un triedro medido
## (alza trasera / boca / empuñadura del autor -> las de la OWK) y escala
## UNIFORME derivada (altura de empuñadura OWK / altura de empuñadura del
## autor). Sin estirados no uniformes, sin inclinaciones de encuadre, sin
## reconstruccion por frame: la pose la manda la animacion del autor.
##
## El arma cuelga de las manos, no al reves: el cuerpo via el hueso PBody (la
## palma que empuña, al que va ligada la corredera del autor al 100%) y el
## cargador via el hueso Pmag (al que va ligado el cargador del autor al
## 100%). Asi Fire/Reload mueven arma y manos juntas, por construccion, y la
## logica solo cuenta municion y decide que animacion toca.
##
## Solo se dibuja la malla de brazos. La pistola del autor (3 mallas) sirve de
## referencia geometrica de autoria y no se renderiza: la unica pistola
## visible es la OWK 19.
## ---------------------------------------------------------------------------
const ARMS_PATH := "res://assets/models/fps_pistol_arms.glb"

var arms_mount: Node3D  # soporte estatico bajo RecoilNode (escala uniforme)
var arms_root: Node3D
var arms_skeleton: Skeleton3D
var arms_player: AnimationPlayer
var arms_mesh_visible: MeshInstance3D
var pbody_attach: BoneAttachment3D
var pmag_attach: BoneAttachment3D
var arms_ok := false


func _install_arms() -> void:
    if pistol_holder == null or not pistol_ok:
        push_error("Los brazos necesitan la OWK construida")
        return
    var packed := load(ARMS_PATH) as PackedScene
    if packed == null:
        push_warning("No se pudieron cargar los brazos: " + ARMS_PATH)
        return
    arms_root = packed.instantiate()
    arms_root.name = "ArmsCransh"
    arms_skeleton = arms_root.find_child("Skeleton3D", true, false) as Skeleton3D
    arms_player = arms_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
    if arms_skeleton == null or arms_player == null:
        push_warning("Los brazos no traen esqueleto utilizable")
        arms_root.queue_free()
        arms_root = null
        return
    # La raiz del GLB trae su propia rotacion de Sketchfab: no se sobrescribe
    # su transform, se cuelga bajo el soporte y se mueve el soporte.
    var holder := Node3D.new()
    holder.name = "ArmsMount"
    recoil_node.add_child(holder)
    holder.add_child(arms_root)
    arms_mount = holder

    # Mallas del asset: la de brazos es la de mas vertices; el resto es la
    # pistola del autor (corredera ligada a Rif, armazon a PBody y cargador a
    # Pmag, cada una al 100% a su hueso). Criterio por hueso dominante, no por
    # nombre: el importador las renombra a Object_N.
    var meshes := _collect_meshes(arms_root)
    var arms_mesh: MeshInstance3D = null
    var most := -1
    for m in meshes:
        var c := _mesh_vert_count(m)
        if c > most:
            most = c
            arms_mesh = m
    arms_mesh_visible = arms_mesh
    var gun_meshes := {"slide": null, "frame": null, "mag": null}
    var hidden := 0
    for m in meshes:
        if m == arms_mesh:
            continue
        m.visible = false
        hidden += 1
        var dom := _dominant_bone(m)
        if dom.begins_with("Pmag"):
            gun_meshes["mag"] = m
        elif dom.begins_with("Rif"):
            gun_meshes["slide"] = m
        elif dom.begins_with("PBody"):
            gun_meshes["frame"] = m
    print("ARMS_MALLAS total=", meshes.size(), " brazos=", arms_mesh.name,
        " verts=", most, " ocultas=", hidden,
        " ref_pistola=", [gun_meshes["slide"] != null, gun_meshes["frame"] != null, gun_meshes["mag"] != null])
    if gun_meshes["slide"] == null or gun_meshes["frame"] == null or gun_meshes["mag"] == null:
        push_warning("Falta alguna pieza de referencia del autor: el montaje pierde su patron")
        holder.queue_free()
        arms_root = null
        return

    # Reposo determinista antes de medir: Idle en t=0.
    _park_arms("FPS_Pistol_Idle", 0.0)
    # Triedro del autor en espacio de arms_root + triedro OWK en marco del arma.
    var feats := _author_features(gun_meshes)
    var b_auth := _triad(feats["rear"], feats["muzzle"], feats["grip"])
    var b_gun := _triad(sight_marker.position, muzzle.position, pistol_grip_local)
    # Escala UNIFORME: la altura de empuñadura manda (es lo que envuelve la
    # mano). Derivada, no elegida: empuñadura OWK / empuñadura del autor.
    var owk_frame_h := _owk_frame_height()
    arms_scale = clampf(owk_frame_h / maxf(feats["frame_h"], 0.0001), 0.5, 1.0)
    var r := b_gun * b_auth.inverse()
    var scaled_r := r.scaled(Vector3(arms_scale, arms_scale, arms_scale))
    # Anclaje en la EMPUÑADURA (lo que tocan las manos), no en el alza: las
    # manos quedan exactas por construccion y el ADS resuelve la mira donde
    # caiga (ver _solve_ads).
    holder.transform = Transform3D(scaled_r, pistol_grip_local - scaled_r * feats["grip"])
    var grip_err: float = (holder.transform * feats["grip"] - pistol_grip_local).length() * 1000.0
    var rear_err: float = (holder.transform * feats["rear"] - sight_marker.position).length() * 1000.0
    print("ARMS_MONTAJE escala=", snappedf(arms_scale, 0.0001),
        " empuñadura_owk_mm=", snappedf(owk_frame_h * 1000.0, 0.1),
        " empuñadura_autor_mm=", snappedf(feats["frame_h"] * 1000.0, 0.1),
        " residuo_empuñadura_mm=", snappedf(grip_err, 0.1),
        " residuo_mira_mm=", snappedf(rear_err, 0.1))
    print("ARMS_PUNTOS autor tras=", (feats["rear"] as Vector3).snapped(Vector3(0.001, 0.001, 0.001)),
        " boca=", (feats["muzzle"] as Vector3).snapped(Vector3(0.001, 0.001, 0.001)),
        " empu=", (feats["grip"] as Vector3).snapped(Vector3(0.001, 0.001, 0.001)),
        " owk tras=", sight_marker.position.snapped(Vector3(0.001, 0.001, 0.001)),
        " boca=", muzzle.position.snapped(Vector3(0.001, 0.001, 0.001)),
        " empu=", pistol_grip_local.snapped(Vector3(0.001, 0.001, 0.001)))

    # El arma cuelga de las manos: cuerpo bajo PBody, cargador bajo Pmag.
    # El local de cada soporte se calcula para conservar el global de reposo
    # exacto (cadenas locales, sin depender del flush de transforms).
    var pbody := _find_bone("PBody")
    var pmag := _find_bone("Pmag")
    if pbody < 0 or pmag < 0:
        push_warning("Sin huesos PBody/Pmag: no se puede colgar el arma de las manos")
        holder.queue_free()
        arms_root = null
        return
    pbody_attach = BoneAttachment3D.new()
    pbody_attach.name = "PBodySocket"
    pbody_attach.bone_idx = pbody
    arms_skeleton.add_child(pbody_attach)
    pmag_attach = BoneAttachment3D.new()
    pmag_attach.name = "PmagSocket"
    pmag_attach.bone_idx = pmag
    arms_skeleton.add_child(pmag_attach)
    arms_skeleton.force_update_all_bone_transforms()
    var pbody_in_recoil: Transform3D = _bone_in_recoil(pbody)
    var pmag_in_recoil: Transform3D = _bone_in_recoil(pmag)
    _reparent_keep(pistol_holder, pbody_attach, pbody_in_recoil, _local_chain(pistol_holder, recoil_node))
    _reparent_keep(pistol_mag_node, pmag_attach, pmag_in_recoil, _local_chain(pistol_mag_node, recoil_node))
    _darken_arms()
    arms_ok = true
    _play_arms_anim("FPS_Pistol_Idle", true)
    print("ARMS_CRANSH ok manos_mandan anim=", arms_player.get_animation_list())


## Todas las mallas bajo una raiz.
func _collect_meshes(root_node: Node) -> Array:
    var out: Array = []
    var stack: Array = [root_node]
    while not stack.is_empty():
        var n = stack.pop_back()
        if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
            out.append(n)
        for c in n.get_children():
            stack.append(c)
    return out


func _mesh_vert_count(mi: MeshInstance3D) -> int:
    var c := 0
    for si in range(mi.mesh.get_surface_count()):
        c += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    return c


## Hueso con mas peso acumulado en la malla (su dueño de facto).
func _dominant_bone(mi: MeshInstance3D) -> String:
    var acc := {}
    for si in range(mi.mesh.get_surface_count()):
        var arrays := mi.mesh.surface_get_arrays(si)
        if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
            continue
        var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
        for vi in range(n):
            for k in range(4):
                var w: float = weights[vi * 4 + k]
                if w > 0.0:
                    var b: int = bones[vi * 4 + k]
                    acc[b] = float(acc.get(b, 0.0)) + w
    var best := -1
    var best_w := 0.0
    for b in acc:
        if float(acc[b]) > best_w:
            best_w = float(acc[b])
            best = b
    if best < 0 or arms_skeleton == null:
        return ""
    return arms_skeleton.get_bone_name(best)


func _find_bone(prefix: String) -> int:
    for b in range(arms_skeleton.get_bone_count()):
        if arms_skeleton.get_bone_name(b).begins_with(prefix):
            return b
    return -1


## Deja una animacion de brazos aparcada en un instante exacto (medicion).
func _park_arms(short_name: String, t: float) -> bool:
    if arms_player == null:
        return false
    for candidate in arms_player.get_animation_list():
        if candidate == short_name or candidate.ends_with("|" + short_name):
            arms_player.play(candidate)
            arms_player.seek(t, true)
            arms_skeleton.force_update_all_bone_transforms()
            return true
    return false


## Vértices de una malla en espacio de arms_root, en reposo, con el skinning
## REAL (pose de reposo por inversa de bind por vertice). Sin esto se mide el
## espacio de bind como si fuera el de reposo y el montaje cae en un espacio de
## fantasia: los numeros cierran (residuo 0) pero las manos no tocan el arma.
func _author_mesh_verts(mi: MeshInstance3D) -> PackedVector3Array:
    var out := PackedVector3Array()
    var skel_in_root: Transform3D = _local_chain(arms_skeleton, arms_root)
    var bind_inv := {}
    var skin := mi.skin
    if skin != null:
        for i in range(skin.get_bind_count()):
            var b := arms_skeleton.find_bone(skin.get_bind_name(i))
            if b >= 0:
                bind_inv[b] = skin.get_bind_pose(i)
    var rest_of := {}
    for si in range(mi.mesh.get_surface_count()):
        var arrays := mi.mesh.surface_get_arrays(si)
        if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
            continue
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        if arrays[Mesh.ARRAY_BONES] == null or bind_inv.is_empty():
            for v in verts:
                out.append(skel_in_root * v)
            continue
        var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        for vi in range(verts.size()):
            var acc := Vector3.ZERO
            for k in range(4):
                var w: float = weights[vi * 4 + k]
                if w <= 0.0:
                    continue
                var b: int = bones[vi * 4 + k]
                if not bind_inv.has(b):
                    continue
                if not rest_of.has(b):
                    rest_of[b] = arms_skeleton.get_bone_global_rest(b)
                acc += w * ((rest_of[b] as Transform3D) * (bind_inv[b] as Transform3D) * verts[vi])
            out.append(skel_in_root * acc)
    return out


## Rasgos de la pistola del autor en espacio de arms_root: al mirar atras, la
## boca delante (extremos del eje largo), empuñadura abajo-atras y altura del
## armazon. Ejes y signos derivados de la propia geometria.
func _author_features(gun_meshes: Dictionary) -> Dictionary:
    var slide_v := _author_mesh_verts(gun_meshes["slide"])
    var frame_v := _author_mesh_verts(gun_meshes["frame"])
    var mag_v := _author_mesh_verts(gun_meshes["mag"])
    var all_v := PackedVector3Array()
    all_v.append_array(slide_v)
    all_v.append_array(frame_v)
    var box := _bounds(all_v)
    var order := [0, 1, 2]
    order.sort_custom(func(a, b): return box.size[a] > box.size[b])
    var ax_l: int = order[0]
    var ax_h: int = order[1]
    var ax_w: int = order[2]
    var unit: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
    # Arriba: la corredera queda por encima del armazon. Delante: el cargador
    # queda por detras de la corredera.
    var s_h := 1.0 if _centroid(slide_v)[ax_h] > _centroid(frame_v)[ax_h] else -1.0
    var s_l := 1.0 if _centroid(slide_v)[ax_l] > _centroid(mag_v)[ax_l] else -1.0
    var up: Vector3 = unit[ax_h] * s_h
    var fwd: Vector3 = unit[ax_l] * s_l
    var frame_box := _bounds(frame_v)
    print("ARMS_CAJAS ejes=", [ax_l, ax_h, ax_w], " caja_total=", box.size.snapped(Vector3(0.001, 0.001, 0.001)),
        " corredera=", _bounds(slide_v).size.snapped(Vector3(0.001, 0.001, 0.001)),
        " armazon=", frame_box.size.snapped(Vector3(0.001, 0.001, 0.001)),
        " arriba=", up.snapped(Vector3(0.01, 0.01, 0.01)), " adelante=", fwd.snapped(Vector3(0.01, 0.01, 0.01)))
    # Trasera: el 15% mas posterior, de ahi el 20% mas alto (el alza).
    # Boca: el 6% mas anterior. Empuñadura: mitad posterior del armazon, el 25%
    # mas bajo (la palma). Todo por direcciones, sin suponer ejes.
    var rear_c := _band_dir(all_v, -fwd, 0.15, up, 0.20)
    var muzzle_c := _band_dir(all_v, fwd, 0.06, Vector3.ZERO, 0.0)
    var grip_c := _band_dir(frame_v, -fwd, 0.45, -up, 0.25)
    return {"rear": rear_c, "muzzle": muzzle_c, "grip": grip_c,
        "frame_h": frame_box.size[ax_h]}


## Media de los vertices en la franja superior de una direccion (los mas
## adelantados si es el avance, los mas altos si es la vertical). Con `dir2` se
## exige ademas estar en su franja superior; con Vector3.ZERO se omite.
func _band_dir(verts: PackedVector3Array, dir: Vector3, frac: float, dir2: Vector3, frac2: float) -> Vector3:
    if verts.is_empty():
        return Vector3.ZERO
    var cut := _dir_cut(verts, dir, frac)
    var cut2 := _dir_cut(verts, dir2, frac2) if dir2.length_squared() > 0.5 else 0.0
    var sum := Vector3.ZERO
    var n := 0
    for v in verts:
        if v.dot(dir) < cut:
            continue
        if dir2.length_squared() > 0.5 and v.dot(dir2) < cut2:
            continue
        sum += v
        n += 1
    if n == 0:
        return _centroid(verts)
    return sum / float(n)


func _dir_cut(verts: PackedVector3Array, dir: Vector3, frac: float) -> float:
    var vals: Array = []
    for v in verts:
        vals.append(v.dot(dir))
    vals.sort()
    if vals.is_empty():
        return 0.0
    return vals[clampi(int(vals.size() * (1.0 - frac)), 0, vals.size() - 1)]


## Triedro origen+(a: eje X, b: plano XY) para el montaje.
func _triad(origin: Vector3, a: Vector3, b: Vector3) -> Basis:
    var f1: Vector3 = (a - origin).normalized()
    var tmp: Vector3 = b - origin
    var f2: Vector3 = (tmp - f1 * tmp.dot(f1)).normalized()
    return Basis(f1, f2, f1.cross(f2))


## Altura del armazon OWK en el marco del arma (para derivar la escala).
func _owk_frame_height() -> float:
    if not pistol_parts.has("Frame") or pistol_holder == null:
        return 0.13
    var verts := PackedVector3Array()
    # _part_verts en espacio del holder YA es marco del arma (la alineacion vive
    # en la raiz del GLB, bajo el holder).
    verts.append_array(_part_verts(pistol_holder, pistol_parts["Frame"], []))
    if verts.is_empty():
        return 0.13
    return _bounds(verts).size.y


## Global de un hueso expresado en espacio de recoil_node (cadenas locales).
func _bone_in_recoil(bone: int) -> Transform3D:
    var mount_in_recoil: Transform3D = (arms_mount as Node3D).transform
    var skel_in_mount: Transform3D = _local_chain(arms_skeleton, arms_mount)
    return mount_in_recoil * skel_in_mount * arms_skeleton.get_bone_global_pose(bone)


## Cuelga `node` bajo `attach` conservando su transform en espacio de recoil.
func _reparent_keep(node: Node3D, attach: BoneAttachment3D, attach_in_recoil: Transform3D, node_in_recoil: Transform3D) -> void:
    node.get_parent().remove_child(node)
    attach.add_child(node)
    node.transform = attach_in_recoil.affine_inverse() * node_in_recoil


## Guantes y mangas a negro de referencia: se conserva la textura del autor
## (detalle, normal, rugosidad) y solo baja el albedo. Sin esto el conjunto
## canta en caqui frente a la referencia de guante negro.
func _darken_arms() -> void:
    if arms_mesh_visible == null or arms_mesh_visible.mesh == null:
        return
    for si in range(arms_mesh_visible.mesh.get_surface_count()):
        var m: Material = arms_mesh_visible.get_surface_override_material(si)
        if m == null:
            m = arms_mesh_visible.mesh.surface_get_material(si)
        if m is StandardMaterial3D:
            var src := m as StandardMaterial3D
            var dark := src.duplicate() as StandardMaterial3D
            dark.albedo_color = Color(0.09, 0.09, 0.10, 1.0)
            # La textura/normal del asset se conserva, pero el guante es
            # tela/cuero y no una superficie metálica. Hacer explícita esta
            # respuesta evita que el pulso de boca produzca reflejos dorados.
            dark.metallic = 0.0
            # El GLB trae un mapa packed metallic-roughness con el canal
            # metálico a 1.0. La rugosidad se mantiene abajo; este canal no
            # puede seguir gobernando la respuesta del guante.
            dark.metallic_texture = null
            dark.roughness = 1.0
            dark.metallic_specular = 0.28
            arms_mesh_visible.set_surface_override_material(si, dark)
            print("ARMS_GUANTE superficie ", si, " albedo_origen=", src.albedo_color,
                " metallic=", src.metallic, " roughness=", src.roughness,
                " metallic_tex=", src.metallic_texture != null,
                " roughness_tex=", src.roughness_texture != null,
                " normal_tex=", src.normal_texture != null,
                " -> metallic=", dark.metallic, " roughness=", dark.roughness)


func _play_arms_anim(short_name: String, loop := false) -> bool:
    if not arms_ok or arms_player == null:
        return false
    var resolved := ""
    for candidate in arms_player.get_animation_list():
        if candidate == short_name or candidate.ends_with("|" + short_name):
            resolved = candidate
            break
    if resolved == "":
        return false
    arms_player.play(resolved, -1.0, 1.0)
    if not loop:
        var idle := _resolve_arms_idle()
        if idle != "":
            arms_player.queue(idle)
    return true


func _resolve_arms_idle() -> String:
    if arms_player == null:
        return ""
    for candidate in arms_player.get_animation_list():
        if candidate.ends_with("FPS_Pistol_Idle"):
            return candidate
    return ""


## Coloca boca, alza real (trasera+delantera) y puerto midiendo la OWK.
##
## Los cuatro marcadores cuelgan del cuerpo del arma y se fijan UNA vez desde
## su geometria. Nada los vuelve a tocar: en particular el ADS NO los mueve
## (antes se recalibraban desde la pose de captura y el test pasaba aunque la
## mira visible no estuviese alineada). La autoridad es la mira que se ve.
func _rebuild_markers_from_pistol(inst: Node3D, holder: Node3D) -> void:
    gun_frame_marker_root(holder)
    var weapon_verts := PackedVector3Array()
    for part_name in pistol_parts:
        if part_name == "Shell" or part_name == "Bullet":
            continue
        weapon_verts.append_array(_part_verts(holder, pistol_parts[part_name], []))
    if weapon_verts.is_empty():
        push_error("No se pudo medir el arma nueva para recolocar los marcadores")
        return
    gun_box = _bounds(weapon_verts)
    muzzle.position = _band_centroid(weapon_verts, gun_box, 0.0, 0.04, 0.0, 1.0)
    sight_marker.position = _band_centroid(weapon_verts, gun_box, 0.80, 1.0, 0.90, 1.0)
    front_marker.position = _band_centroid(weapon_verts, gun_box, 0.0, 0.10, 0.88, 1.0)
    ejection_port.position = _ejection_point(weapon_verts, gun_box)
    wrist_local = Vector3(0.0, gun_box.position.y + gun_box.size.y * 0.55,
        gun_box.position.z + gun_box.size.z + 0.030)
    print("PISTOL_MARCADORES mira_tras=", sight_marker.position.snapped(Vector3(0.001,0.001,0.001)),
        " mira_del=", front_marker.position.snapped(Vector3(0.001,0.001,0.001)),
        " boca=", muzzle.position.snapped(Vector3(0.001,0.001,0.001)),
        " caja=", gun_box.size.snapped(Vector3(0.001,0.001,0.001)))


## Crea los nodos de referencia colgados del cuerpo del arma (marco del arma).
func gun_frame_marker_root(holder: Node3D) -> void:
    muzzle = Node3D.new()
    muzzle.name = "Muzzle"
    holder.add_child(muzzle)
    sight_marker = Node3D.new()
    sight_marker.name = "SightRear"
    holder.add_child(sight_marker)
    front_marker = Node3D.new()
    front_marker.name = "SightFront"
    holder.add_child(front_marker)
    ejection_port = Node3D.new()
    ejection_port.name = "EjectionPort"
    holder.add_child(ejection_port)
    _build_flash()


## Calibra las dos luces del viewmodel para la OWK.
##
## El asset trae albedo PBR de verdad (~0.12 tipico y hasta 0.5 en las zonas
## claras): con la energia original el arma salia quemada (medido, 4-10% de sus
## pixeles recortados a blanco). Se baja la energia para que haya difusa sin
## recorte. No se toca ninguna textura del asset.
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


## Vector, en unidades del padre de `node`, que corresponde a UN METRO del arma
## en la dirección `weapon_dir` (medida en el frame del arma).
func _meters_in_parent(reference: Node3D, node: Node3D, rot: Basis, weapon_dir: Vector3) -> Vector3:
    var parent_in_ref: Transform3D = _local_chain(node.get_parent(), reference)
    return parent_in_ref.basis.inverse() * (rot.transposed() * weapon_dir) / pistol_scale


## Dirección de `dir_in_ref` expresada en el espacio local del padre de `node`.
func _dir_in_parent(reference: Node3D, node: Node3D, dir_in_ref: Vector3) -> Vector3:
    var parent_in_ref: Transform3D = _local_chain(node.get_parent(), reference)
    return (parent_in_ref.basis.inverse() * dir_in_ref).normalized()


## Traduce el estado mecánico (que no cambia) a transforms de las piezas.
func _apply_pistol_parts() -> void:
    if not pistol_ok:
        return
    var slide := pistol_parts["Slide"] as Node3D
    slide.transform.origin = (pistol_rest["Slide"] as Transform3D).origin + pistol_slide_units * slide_pos

    var trigger := pistol_parts["Trigger"] as Node3D
    var trig := Basis(pistol_trigger_axis, -0.30 * trigger_visual)
    trigger.transform = Transform3D(trig, pistol_trigger_pivot - trig * pistol_trigger_pivot)
    # Cargador: sin escritura por frame. Cuelga del hueso Pmag del autor (al que
    # va ligado su cargador al 100%), asi que la animacion de recarga lo saca y
    # lo devuelve en fase con las manos por construccion. La logica solo cuenta
    # municion (ver _seat_reload_mag) y decide que animacion toca.
