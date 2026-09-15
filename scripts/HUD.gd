extends CanvasLayer

var player
var post: ColorRect
var post_mat: ShaderMaterial
var crosshair_lines: Array[ColorRect] = []
var ammo_label: Label
var reserve_label: Label
var reload_label: Label
var clock_label: Label
var rec_label: Label
var rec_dot: ColorRect
var bottom_label: Label
var fps_label: Label
var hitmarker: Label
var hitmarker_time := 0.0
var clock_timer := 0.0


func _ready() -> void:
    layer = 0
    _build_post()
    _build_hud()
    process_mode = Node.PROCESS_MODE_ALWAYS


func setup(p) -> void:
    player = p
    if player != null and is_instance_valid(player.weapon):
        player.weapon.ammo_changed.connect(_on_ammo_changed)
    Ballistics.target_hit.connect(_on_target_hit)
    _on_ammo_changed(player.weapon.mag if player != null else 17, 1, 68, false)


func _build_post() -> void:
    post = ColorRect.new()
    post.set_anchors_preset(Control.PRESET_FULL_RECT)
    post.color = Color.WHITE
    post.mouse_filter = Control.MOUSE_FILTER_IGNORE
    post_mat = ShaderMaterial.new()
    post_mat.shader = preload("res://shaders/bodycam.gdshader")
    post.material = post_mat
    add_child(post)


func _build_hud() -> void:
    rec_dot = ColorRect.new()
    rec_dot.color = Color(1.0, 0.18, 0.12, 1.0)
    rec_dot.size = Vector2(8, 8)
    rec_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(rec_dot)

    rec_label = _make_label("REC", 13, Color(1.0, 0.22, 0.16, 1.0))
    add_child(rec_label)

    clock_label = _make_label("--:--:--", 13, Color(0.9, 0.92, 0.95, 0.85))
    clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(clock_label)

    bottom_label = _make_label("FLOWFIRE LAB · BODY CAM 03 · 1080P", 12, Color(0.9, 0.92, 0.95, 0.62))
    bottom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(bottom_label)

    fps_label = _make_label("60 FPS", 12, Color(0.85, 0.9, 0.95, 0.6))
    fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    add_child(fps_label)

    ammo_label = _make_label("18", 48, Color(0.95, 0.97, 1.0, 0.95))
    ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    add_child(ammo_label)

    reserve_label = _make_label("/ 68", 22, Color(0.85, 0.88, 0.94, 0.8))
    reserve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    add_child(reserve_label)

    reload_label = _make_label("RECARGAR (R)", 22, Color(1.0, 0.85, 0.3, 1.0))
    reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(reload_label)

    hitmarker = _make_label("✕", 30, Color(1, 1, 1, 0))
    hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    hitmarker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    add_child(hitmarker)

    for _i in range(4):
        var line := ColorRect.new()
        line.color = Color(0.92, 0.95, 1.0, 0.9)
        line.mouse_filter = Control.MOUSE_FILTER_IGNORE
        crosshair_lines.append(line)
        add_child(line)


func _make_label(text: String, size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)
    return label


func _on_ammo_changed(mag: int, chamber: int, reserve: int, reloading: bool) -> void:
    var display := mag + chamber
    ammo_label.text = str(display)
    reserve_label.text = "/ " + str(reserve)
    reload_label.visible = reloading or (display <= 0)
    reload_label.text = "RECARGANDO" if reloading else "RECARGAR (R)"


func _on_target_hit(zone: String) -> void:
    hitmarker_time = 0.13
    hitmarker.modulate.a = 1.0
    hitmarker.add_theme_color_override("font_color", Color(1.0, 0.2, 0.12) if zone == "CABEZA" else Color(1, 1, 1))


func _process(delta: float) -> void:
    var viewport_size := get_viewport().get_visible_rect().size
    var center := viewport_size * 0.5

    rec_dot.position = Vector2(center.x - 62, 16)
    rec_label.position = Vector2(center.x - 46, 11)
    clock_label.position = Vector2(center.x - 30, 11)
    clock_label.size = Vector2(120, 20)
    bottom_label.position = Vector2(center.x - 300, viewport_size.y - 32)
    bottom_label.size = Vector2(600, 20)
    fps_label.position = Vector2(18, 14)
    fps_label.size = Vector2(120, 20)

    ammo_label.position = Vector2(viewport_size.x - 210, viewport_size.y - 116)
    ammo_label.size = Vector2(180, 70)
    reserve_label.position = Vector2(viewport_size.x - 210, viewport_size.y - 52)
    reserve_label.size = Vector2(180, 30)
    reload_label.position = Vector2(center.x - 120, viewport_size.y - 92)
    reload_label.size = Vector2(240, 30)
    hitmarker.position = Vector2(center.x - 40, center.y - 42)
    hitmarker.size = Vector2(80, 80)

    var speed_now = player.current_speed if player != null else 0.0
    var aim_amount = player.weapon.aim_blend if player != null else 0.0
    var gap = 10.0 + speed_now * 1.4 + (18.0 if (player != null and player.weapon.reloading) else 0.0)
    if aim_amount > 0.55:
        gap = 4.0
    _set_cross_line(0, Vector2(2, 9), Vector2(center.x - 1, center.y - gap - 9), Color(0.92, 0.95, 1.0, 0.35 + (1.0 - aim_amount) * 0.55))
    _set_cross_line(1, Vector2(2, 9), Vector2(center.x - 1, center.y + gap), Color(0.92, 0.95, 1.0, 0.35 + (1.0 - aim_amount) * 0.55))
    _set_cross_line(2, Vector2(9, 2), Vector2(center.x - gap - 9, center.y - 1), Color(0.92, 0.95, 1.0, 0.35 + (1.0 - aim_amount) * 0.55))
    _set_cross_line(3, Vector2(9, 2), Vector2(center.x + gap, center.y - 1), Color(0.92, 0.95, 1.0, 0.35 + (1.0 - aim_amount) * 0.55))

    if hitmarker_time > 0.0:
        hitmarker_time -= delta
        hitmarker.modulate.a = maxf(0.0, hitmarker_time / 0.13)

    clock_timer -= delta
    if clock_timer <= 0.0:
        clock_timer = 1.0
        clock_label.text = Time.get_time_string_from_system(false)

    fps_label.text = str(Engine.get_frames_per_second()) + " FPS"

    var shot_pulse = player.weapon.shot_pulse if player != null else 0.0
    var turn = clampf(player.yaw_vel / 7.0, -1.0, 1.0) if player != null else 0.0
    post_mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
    post_mat.set_shader_parameter("aim_amount", aim_amount)
    post_mat.set_shader_parameter("speed_amount", clampf(speed_now / 6.3, 0.0, 1.0))
    post_mat.set_shader_parameter("exposure_pulse", shot_pulse)
    post_mat.set_shader_parameter("blur_amount", clampf(speed_now * 0.0011 + absf(turn) * 0.0016 + shot_pulse * 0.012, 0.0, 0.018))
    post_mat.set_shader_parameter("blur_dir", Vector2(-turn * 0.7, 0.0))
    post_mat.set_shader_parameter("grain_amount", 0.05 + clampf(speed_now / 6.3, 0.0, 1.0) * 0.02)


func _set_cross_line(index: int, size: Vector2, pos: Vector2, color: Color) -> void:
    var line := crosshair_lines[index]
    line.size = size
    line.position = pos
    line.color = color
