extends CharacterBody3D

const MOUSE_SENS := 0.00175
const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.3
const CROUCH_SPEED := 2.0

var camera: Camera3D
var weapon
var mouse_captured := false

var yaw := 0.0
var pitch := 0.0
var yaw_target := 0.0
var pitch_target := 0.0
var yaw_vel := 0.0
var pitch_vel := 0.0
var look_delta := Vector2.ZERO

var cam_y := 1.62
var cam_y_vel := 0.0
var body_lag := Vector3.ZERO
var prev_velocity := Vector3.ZERO

var bob_phase := 0.0
var step_accum := 0.0
var breath_phase := 0.0
var lean := 0.0
var current_speed := 0.0
var current_move_norm := 0.0
var sprinting := false
var crouching := false
var target_fov := 82.0

var bob_x := 0.0
var bob_y := 0.0
var bob_roll := 0.0

var recoil_pitch := 0.0
var recoil_yaw := 0.0
var recoil_roll := 0.0
var recoil_pitch_vel := 0.0
var recoil_yaw_vel := 0.0
var recoil_roll_vel := 0.0

var _last_local_move := Vector2.ZERO


func _ready() -> void:
    collision_layer = 2
    collision_mask = 1
    _build_body()
    _build_camera()
    _build_weapon()


func _build_body() -> void:
    var shape := CapsuleShape3D.new()
    shape.radius = 0.34
    shape.height = 1.7
    var collider := CollisionShape3D.new()
    collider.shape = shape
    collider.position = Vector3(0, 0.85, 0)
    add_child(collider)


func _build_camera() -> void:
    camera = Camera3D.new()
    camera.name = "Camera"
    camera.position = Vector3(0, 1.62, 0)
    camera.fov = 82.0
    camera.near = 0.04
    camera.far = 350.0
    camera.current = true
    add_child(camera)


func _build_weapon() -> void:
    var rig := Node3D.new()
    rig.name = "WeaponRig"
    # El arma va CENTRADA en la pantalla (como en una bodycam real: la pistola
    # y el brazo bajan por el centro del encuadre), no desplazada a la derecha.
    rig.position = Vector3(0.0, -0.185, -0.345)
    rig.rotation_degrees = Vector3(0, 0.0, 0)
    camera.add_child(rig)
    weapon = preload("res://scripts/Glock.gd").new()
    weapon.name = "Glock"
    rig.add_child(weapon)
    weapon.setup(camera)
    weapon.shot_fired.connect(_on_shot_fired)
    _last_local_move = Vector2.ZERO


func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_ESCAPE:
                _release_mouse()
            KEY_R:
                weapon.start_reload()
            KEY_F:
                if mouse_captured:
                    weapon.force_fire_once()

    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if not mouse_captured:
                if event.pressed:
                    _capture_mouse()
            else:
                if event.pressed:
                    weapon.press_trigger()
                else:
                    weapon.release_trigger()
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            if mouse_captured:
                weapon.set_aim(event.pressed)

    if event is InputEventMouseMotion and mouse_captured:
        yaw_target -= event.relative.x * MOUSE_SENS
        pitch_target = clampf(pitch_target - event.relative.y * MOUSE_SENS, -1.38, 1.38)
        # Evita saltos enormes al girar rápido.
        look_delta = Vector2(
            clampf(event.relative.x, -12.0, 12.0),
            clampf(event.relative.y, -12.0, 12.0)
        )


func _capture_mouse() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    mouse_captured = true


func _release_mouse() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    mouse_captured = false
    weapon.release_trigger()
    weapon.set_aim(false)


func _physics_process(delta: float) -> void:
    var input_x := (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
    var input_z := (1.0 if Input.is_key_pressed(KEY_W) else 0.0) - (1.0 if Input.is_key_pressed(KEY_S) else 0.0)
    sprinting = Input.is_key_pressed(KEY_SHIFT) and input_z > 0.0 and not crouching
    crouching = Input.is_key_pressed(KEY_CTRL)

    var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
    var right := Vector3(cos(yaw), 0.0, -sin(yaw))
    var wish := right * input_x + forward * input_z
    if wish.length_squared() > 1.0:
        wish = wish.normalized()

    var speed := WALK_SPEED
    if crouching:
        speed = CROUCH_SPEED
    elif sprinting:
        speed = SPRINT_SPEED
    if input_z < 0.0:
        speed *= 0.78
    elif input_x != 0.0 and input_z >= 0.0:
        speed *= 0.9

    var target_velocity := wish * speed
    var accel := 28.0 if wish.length_squared() > 0.01 else 20.0
    var blend := 1.0 - exp(-accel * delta / 4.0)
    velocity.x = lerpf(velocity.x, target_velocity.x, blend)
    velocity.z = lerpf(velocity.z, target_velocity.z, blend)

    if not is_on_floor():
        velocity.y -= GRAVITY_VALUE * delta
    else:
        velocity.y = -0.5

    move_and_slide()
    current_speed = Vector2(velocity.x, velocity.z).length()
    current_move_norm = clampf(current_speed / WALK_SPEED, 0.0, 1.0)

    var local_strafe := velocity.dot(right) / WALK_SPEED
    var local_forward := velocity.dot(forward) / WALK_SPEED
    _last_local_move = Vector2(local_strafe, local_forward)

    if current_speed > 0.22:
        bob_phase += delta * (1.8 + current_speed * 1.45)
        step_accum += current_speed * delta
        if step_accum > 1.45:
            step_accum -= 1.45
            GameAudio.play_2d("footstep", 0.0, randf_range(0.92, 1.08))
    else:
        step_accum = 0.0

    bob_x = cos(bob_phase) * 0.0125 * current_move_norm
    bob_y = sin(bob_phase * 2.0) * 0.0185 * current_move_norm
    bob_roll = sin(bob_phase) * 0.013 * current_move_norm


const GRAVITY_VALUE := 9.8


func _process(delta: float) -> void:
    breath_phase += delta

    if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        mouse_captured = false

    var yaw_prev := yaw
    var pitch_prev := pitch
    var follow := 1.0 - exp(-26.0 * delta)
    yaw += (yaw_target - yaw) * follow
    pitch += (pitch_target - pitch) * follow
    var vel_follow := 1.0 - exp(-16.0 * delta)
    yaw_vel += ((yaw - yaw_prev) / maxf(delta, 0.001) - yaw_vel) * vel_follow
    pitch_vel += ((pitch - pitch_prev) / maxf(delta, 0.001) - pitch_vel) * vel_follow
    yaw_vel = clampf(yaw_vel, -14.0, 14.0)
    pitch_vel = clampf(pitch_vel, -14.0, 14.0)
    pitch = clampf(pitch, -1.45, 1.45)
    look_delta = look_delta.lerp(Vector2.ZERO, 1.0 - exp(-20.0 * delta))

    var input_x := (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
    var target_height := 1.1 if crouching else 1.62
    cam_y_vel += ((target_height - cam_y) * 185.0 - cam_y_vel * 21.0) * delta
    cam_y += cam_y_vel * delta

    var accel_world := (velocity - prev_velocity) / maxf(delta, 0.0001)
    prev_velocity = velocity
    var desired_lag := Vector3(-accel_world.x * 0.00042, 0.0, -accel_world.z * 0.00042)
    if desired_lag.length() > 0.026:
        desired_lag = desired_lag.normalized() * 0.026
    var lag_follow := 1.0 - exp(-7.5 * delta)
    body_lag.x = lerpf(body_lag.x, desired_lag.x, lag_follow)
    body_lag.z = lerpf(body_lag.z, desired_lag.z, lag_follow)

    var lean_target := -input_x * 0.038 + clampf(yaw_vel * 0.013, -1.0, 1.0) + bob_roll * 0.55
    lean += (lean_target - lean) * (1.0 - exp(-8.0 * delta))

    var target_fov_local := 82.0
    if weapon.aim_blend > 0.55:
        target_fov_local = 60.0
    elif sprinting:
        target_fov_local = 90.0
    elif crouching:
        target_fov_local = 78.0
    target_fov = target_fov_local
    camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-7.0 * delta))

    var breath_yaw = sin(breath_phase * 0.73 + 1.1) * 0.0011 * (1.0 - weapon.aim_blend * 0.58)
    var breath_pitch = sin(breath_phase * 1.15) * 0.0014 * (1.0 - weapon.aim_blend * 0.58)
    var breath_roll = sin(breath_phase * 0.91 + 0.5) * 0.0010 * (1.0 - weapon.aim_blend * 0.58)

    _update_camera_recoil(delta)

    camera.position = Vector3(
        body_lag.x + bob_x,
        cam_y + bob_y,
        body_lag.z
    )
    camera.rotation = Vector3(
        pitch + breath_pitch - current_move_norm * 0.006 + recoil_pitch,
        yaw + breath_yaw + recoil_yaw,
        lean + bob_roll * 0.6 + breath_roll + recoil_roll
    )

    weapon.set_motion(current_speed, _last_local_move, look_delta)
    weapon.set_sprint(sprinting)


func _update_camera_recoil(delta: float) -> void:
    # Resortes estables (Springs): un hitch de frame no debe volcar la cámara.
    # k/c dan zeta 0.85: la cabeza sube y BAJA sin rebotar, con el pico a
    # ~111 ms y recuperación de ~450 ms. Es la capa más lenta de las cuatro y
    # la que da la masa: no repite el latigazo del arma, lo sigue.
    var k := 90.0
    var c := 16.1
    var pitch := Springs.scalar(recoil_pitch, recoil_pitch_vel, k, c, delta)
    recoil_pitch = pitch.x
    recoil_pitch_vel = pitch.y
    var yaw_pair := Springs.scalar(recoil_yaw, recoil_yaw_vel, k, c, delta)
    recoil_yaw = yaw_pair.x
    recoil_yaw_vel = yaw_pair.y
    var roll := Springs.scalar(recoil_roll, recoil_roll_vel, k, c, delta)
    recoil_roll = roll.x
    recoil_roll_vel = roll.y

    # Clamps: la cámara nunca debe quedarse mirando a otro sitio.
    recoil_pitch = clampf(recoil_pitch, -0.30, 0.30)
    recoil_yaw = clampf(recoil_yaw, -0.25, 0.25)
    recoil_roll = clampf(recoil_roll, -0.25, 0.25)


func _on_shot_fired() -> void:
    # La cámara (la cabeza del operador) sube menos que el arma y tarda más:
    # pico de ~2.5-3.0 grados a ~111 ms con recuperación de ~450 ms. Sólo
    # rotación: un desplazamiento de cámara de unos milímetros no se ve (el
    # viewmodel cuelga de ella y se mueve con ella), así que simular "masa"
    # moviéndola de sitio sería decorativo.
    recoil_pitch_vel += randf_range(1.00, 1.20)
    recoil_yaw_vel += randf_range(-0.20, 0.20)
    recoil_roll_vel += randf_range(-0.35, 0.35)
