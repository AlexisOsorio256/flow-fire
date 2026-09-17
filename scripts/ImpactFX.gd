extends Node3D

const HOLE_ENTRY: Texture2D = preload("res://assets/textures/bullet_hole_entry.png")
const HOLE_EXIT: Texture2D = preload("res://assets/textures/bullet_hole_exit.png")
const SOFT_TEXTURE: Texture2D = preload("res://assets/textures/particle_soft.png")
const SPARK_TEXTURE: Texture2D = preload("res://assets/textures/particle_spark.png")

var decals: Array[MeshInstance3D] = []
# Interruptor para aislar el coste de FX al perfilar. No cambia ninguna regla
# ni el comportamiento por defecto.
var spawning_enabled := true


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS


func spawn_impact(point: Vector3, normal: Vector3, collider: Object, surface: String, is_exit: bool = false) -> void:
    if not spawning_enabled:
        return
    _spawn_decal(point, normal, collider, surface, is_exit)
    _spawn_particles(point, normal, surface, is_exit)
    _spawn_light(point, surface)

    var sound_name := "impact_concrete"
    var volume := 0.0
    match surface:
        "metal":
            sound_name = "impact_metal"
        "wood":
            sound_name = "impact_wood"
        "paper":
            sound_name = "impact_wood"
            volume = -10.0
        "drywall":
            sound_name = "impact_concrete"
            volume = -5.0
        _:
            sound_name = "impact_concrete"
    if not (is_exit and surface == "paper"):
        GameAudio.play_3d(sound_name, point, volume, randf_range(0.92, 1.08))  # volume = ajuste sobre el nivel base


func spawn_muzzle_smoke(point: Vector3, direction: Vector3) -> void:
    if not spawning_enabled:
        return
    var pm := ParticleProcessMaterial.new()
    pm.direction = direction.normalized()
    pm.spread = 24.0
    pm.initial_velocity_min = 0.25
    pm.initial_velocity_max = 0.9
    pm.gravity = Vector3(0, 0.35, 0)
    pm.scale_min = 0.45
    pm.scale_max = 1.8
    pm.color = Color(0.55, 0.55, 0.52, 0.24)
    pm.damping_min = 1.2
    pm.damping_max = 2.0

    var particles := GPUParticles3D.new()
    particles.amount = 7
    particles.lifetime = 0.9
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.process_material = pm
    particles.draw_pass_1 = _particle_quad(SOFT_TEXTURE, Color(0.6, 0.6, 0.58, 0.28), false, Vector2(0.055, 0.055))
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(particles)
    particles.global_position = point
    get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


func _spawn_decal(point: Vector3, normal: Vector3, collider: Object, surface: String, is_exit: bool) -> void:
    var profile: Dictionary = IMPACT_MATERIALS.get(surface, IMPACT_MATERIALS["concrete"])
    var size := 0.026
    match surface:
        "metal":
            size = 0.020
        "paper":
            size = 0.014
        "wood", "drywall":
            size = 0.024
        _:
            size = 0.026
    # La salida no mide lo mismo en todos los materiales: el pladur revienta
    # hacia fuera y el metal apenas deja marca.
    if is_exit:
        size *= float(profile.get("exit_scale", 1.35))

    var quad := QuadMesh.new()
    quad.size = Vector2(size, size)
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = HOLE_EXIT if is_exit else HOLE_ENTRY
    mat.albedo_color = Color(1, 1, 1, 0.98 if is_exit else 1.0)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    mat.roughness = 1.0
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    quad.material = mat

    var decal := MeshInstance3D.new()
    decal.name = "BulletHole"
    decal.mesh = quad
    decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var n := normal.normalized()
    if n.length_squared() < 0.01:
        n = Vector3.UP
    var up_ref := Vector3.UP
    if absf(n.dot(up_ref)) > 0.94:
        up_ref = Vector3.RIGHT
    var x_axis := up_ref.cross(n).normalized()
    if x_axis.length_squared() < 0.01:
        x_axis = Vector3.RIGHT
    var y_axis := n.cross(x_axis).normalized()
    if y_axis.length_squared() < 0.01:
        y_axis = Vector3.FORWARD
    var basis := Basis(x_axis, y_axis, n)
    basis = basis.rotated(n, randf_range(0.0, TAU))
    var pos := point + n * (0.004 + (0.003 if is_exit else 0.0))
    add_child(decal)
    decal.global_transform = Transform3D(basis, pos)

    if collider is Node3D and collider.get_meta("dynamic_decal", false):
        decal.reparent(collider, true)

    decals.append(decal)
    if decals.size() > 160:
        var old: MeshInstance3D = decals.pop_front()
        if is_instance_valid(old):
            old.queue_free()


## Respuesta por material. Cada entrada declara una o dos eyecciones DISTINTAS:
##   dust   - lo que queda en el aire (polvo mineral, yeso, fibra fina)
##   debris - lo que sale disparado y cae (esquirlas, astillas, chispas)
## No son las mismas particulas con otro color: cambian cantidad, velocidad,
## gravedad, tamano, duracion y textura. El papel casi no se mueve; el hormigon
## levanta polvo y esquirlas; la madera, astillas alargadas; el metal, chispas
## con luz. El impacto de salida usa la misma familia pero mas floja, salvo el
## pladur, que revienta hacia fuera.
const IMPACT_MATERIALS := {
    "concrete": {
        "dust": {"amount": 9, "color": Color(0.56, 0.55, 0.52, 0.60), "vel": [0.4, 1.6], "gravity": -2.0, "scale": [0.6, 2.4], "life": 0.85, "size": 0.050, "spread": 62.0},
        "debris": {"amount": 6, "color": Color(0.34, 0.33, 0.31, 0.95), "vel": [2.6, 6.5], "gravity": -13.0, "scale": [0.18, 0.50], "life": 0.50, "size": 0.018, "spread": 70.0},
        "exit_scale": 1.25,
    },
    "drywall": {
        "dust": {"amount": 14, "color": Color(0.82, 0.80, 0.75, 0.72), "vel": [0.5, 2.0], "gravity": -1.4, "scale": [0.8, 3.0], "life": 1.05, "size": 0.058, "spread": 74.0},
        "debris": {"amount": 4, "color": Color(0.72, 0.70, 0.64, 0.90), "vel": [1.8, 4.4], "gravity": -8.0, "scale": [0.30, 0.80], "life": 0.60, "size": 0.026, "spread": 66.0},
        "exit_scale": 1.80,
    },
    "wood": {
        "dust": {"amount": 7, "color": Color(0.46, 0.33, 0.18, 0.62), "vel": [0.5, 2.0], "gravity": -2.6, "scale": [0.5, 1.8], "life": 0.70, "size": 0.044, "spread": 60.0},
        "debris": {"amount": 8, "color": Color(0.35, 0.22, 0.10, 0.98), "vel": [3.4, 8.0], "gravity": -12.0, "scale": [0.30, 0.85], "life": 0.60, "size": 0.030, "spread": 52.0, "stretch": 4.0},
        "exit_scale": 1.50,
    },
    "metal": {
        "debris": {"amount": 18, "color": Color(1.0, 0.72, 0.26, 1.0), "vel": [3.0, 8.0], "gravity": -11.0, "scale": [0.30, 1.10], "life": 0.34, "size": 0.018, "spread": 58.0, "spark": true},
        "dust": {"amount": 5, "color": Color(0.50, 0.50, 0.52, 0.35), "vel": [0.4, 1.4], "gravity": -2.0, "scale": [0.40, 1.20], "life": 0.40, "size": 0.030, "spread": 50.0},
        "exit_scale": 1.15,
    },
    "paper": {
        "dust": {"amount": 4, "color": Color(0.84, 0.81, 0.74, 0.50), "vel": [0.2, 0.8], "gravity": -1.0, "scale": [0.30, 0.90], "life": 0.35, "size": 0.020, "spread": 44.0},
        "exit_scale": 1.10,
    },
}


func _spawn_particles(point: Vector3, normal: Vector3, surface: String, is_exit: bool) -> void:
    var profile: Dictionary = IMPACT_MATERIALS.get(surface, IMPACT_MATERIALS["concrete"])
    var n := normal.normalized()
    # En la salida el material ya viene roto: menos cantidad y mas lenta, salvo
    # el pladur, que se deshace hacia fuera y por eso tiene su propio factor.
    var strength := 0.55 if is_exit else 1.0
    if is_exit and surface == "drywall":
        strength = 1.30
    for key in ["dust", "debris"]:
        if profile.has(key):
            _burst(point + n * 0.01, n, profile[key], strength)


## Una eyeccion concreta. `strength` escala cantidad y velocidad sin cambiar el
## caracter del material (que es lo que lo identifica).
func _burst(point: Vector3, normal: Vector3, spec: Dictionary, strength: float) -> void:
    var spark: bool = spec.get("spark", false)
    var pm := ParticleProcessMaterial.new()
    pm.direction = normal
    pm.spread = float(spec["spread"])
    pm.gravity = Vector3(0, float(spec["gravity"]), 0)
    pm.initial_velocity_min = float(spec["vel"][0]) * strength
    pm.initial_velocity_max = float(spec["vel"][1]) * strength
    pm.scale_min = float(spec["scale"][0])
    pm.scale_max = float(spec["scale"][1])
    pm.color = spec["color"]
    if spark:
        pm.damping_min = 0.4
        pm.damping_max = 0.9
    else:
        pm.damping_min = 0.9
        pm.damping_max = 2.0

    var particles := GPUParticles3D.new()
    var amount := float(spec["amount"])
    particles.amount = maxi(1, int(round(amount * (1.0 if strength >= 1.0 else 0.7 + 0.3 * strength))))
    particles.lifetime = float(spec["life"])
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.process_material = pm
    # La astilla de madera es un sliver alargado, no un quad cuadrado: es lo que
    # la distingue de una particula de polvo a la misma distancia.
    var stretch := float(spec.get("stretch", 1.0))
    var size := float(spec["size"])
    particles.draw_pass_1 = _particle_quad(
        SPARK_TEXTURE if spark else SOFT_TEXTURE,
        spec["color"], spark, Vector2(size * stretch, size / maxf(stretch, 1.0)))
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(particles)
    particles.global_position = point
    get_tree().create_timer(particles.lifetime + 0.5).timeout.connect(particles.queue_free)


func _spawn_light(point: Vector3, surface: String) -> void:
    # La luz no es un sustituto de partículas. Hormigón, yeso, papel y madera
    # levantan polvo/fibra pero no producen un destello que ilumine la sala;
    # sólo el impacto metálico tiene un flash físico breve junto a la chispa.
    if surface != "metal":
        return
    var light := OmniLight3D.new()
    light.omni_range = 0.85
    light.light_energy = 0.9
    light.light_color = Color(1.0, 0.72, 0.34)
    light.shadow_enabled = false
    add_child(light)
    light.global_position = point + Vector3.UP * 0.05
    var tween := create_tween()
    tween.tween_property(light, "light_energy", 0.0, 0.045)
    tween.finished.connect(light.queue_free)


func _particle_quad(texture: Texture2D, color: Color, additive: bool, size: Vector2) -> QuadMesh:
    var quad := QuadMesh.new()
    quad.size = size
    var mat := StandardMaterial3D.new()
    mat.albedo_texture = texture
    mat.albedo_color = color
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    mat.billboard_keep_scale = true
    mat.vertex_color_use_as_albedo = true
    mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    quad.material = mat
    return quad
