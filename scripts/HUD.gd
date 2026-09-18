extends CanvasLayer

var player
var post: ColorRect
var post_mat: ShaderMaterial
var ammo_label: Label
var reserve_label: Label
var reload_label: Label
var clock_label: Label
var rec_label: Label
var rec_dot: ColorRect
var bottom_label: Label
var fps_label: Label
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
    _on_ammo_changed(player.weapon.mag if player != null else 15, 1, 60, false)


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

    reserve_label = _make_label("/ 60", 22, Color(0.85, 0.88, 0.94, 0.8))
    reserve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    add_child(reserve_label)

    reload_label = _make_label("RECARGAR (R)", 22, Color(1.0, 0.85, 0.3, 1.0))
    reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(reload_label)


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
    # Sin mira en pantalla: se apunta con las miras reales del arma (es lo que
    # hace creíble una bodycam).
    var aim_amount = player.weapon.aim_blend if player != null else 0.0

    clock_timer -= delta
    if clock_timer <= 0.0:
        clock_timer = 1.0
        clock_label.text = Time.get_time_string_from_system(false)

    fps_label.text = str(Engine.get_frames_per_second()) + " FPS"

    var shot_pulse = player.weapon.shot_pulse if player != null else 0.0
    post_mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
    post_mat.set_shader_parameter("aim_amount", aim_amount)
    # Sin blur de movimiento ni grano variable: el post sólo da carácter de
    # cámara (lente, viñeta, sensor) y no debe esconder detalle ni con el
    # jugador corriendo.
    post_mat.set_shader_parameter("exposure_pulse", shot_pulse)


