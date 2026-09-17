extends Node3D

## Presentacion de los impactos: marca proyectada, crater segun material y
## eyecciones. NO decide balistica: `Ballistics.gd` dice DONDE y CONTRA QUE, y
## aqui se representa. Autoload.
##
## Cada impacto se compone de tres cosas que NO son lo mismo:
##   1. Agujero tallado: un embudo de dos anillos apoyado en la superficie, con
##      el interior hundido y el labio enrasado. Geometria OPACA: en este
##      renderer ni el Decal nativo dibuja ni el alfa de una calcomania llega al
##      fragmento.
##   2. Eyecciones: polvo y escombros por material (ver IMPACT_MATERIALS).
##
## Entrada y salida tienen CARACTER distinto (no es la entrada escalada): la
## salida es mas ancha, mas plana y revienta hacia fuera, y en pladur y madera
## se lleva material.

const HOLE_ENTRY: Texture2D = preload("res://assets/textures/bullet_hole_entry.png")
const HOLE_EXIT: Texture2D = preload("res://assets/textures/bullet_hole_exit.png")
const SOFT_TEXTURE: Texture2D = preload("res://assets/textures/particle_soft.png")
const SPARK_TEXTURE: Texture2D = preload("res://assets/textures/particle_spark.png")

## Tope de impactos visibles. Mobile no aguanta miles de marcas eternas y una
## lista pequena basta: al pasarse, la mas vieja se libera. Sin pool manager.
const MAX_HOLES := 96
## Diametro EXTERIOR del agujero por material. Es exagerado respecto al real (un
## 9 mm deja ~9 mm): a tamano fisico el agujero es un punto de 4 mm ilegible a
## dos metros, que es lo que se ve como nada. El interior (lo que se lee como
## hueco) es el 34% de esto. La exageracion es del agujero, no de la profundidad.
const HOLE_SIZE := {
    "concrete": 0.055,
    "drywall": 0.050,
    "wood": 0.050,
    "metal": 0.038,
    "paper": 0.030,
    "flesh": 0.045,
}

var _holes: Array[Node] = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS


func spawn_impact(point: Vector3, normal: Vector3, collider: Object, surface: String, is_exit: bool = false) -> void:
    _spawn_decal(point, normal, collider, surface, is_exit)
    _spawn_particles(point, normal, surface, is_exit)
    _spawn_light(point, surface)

    # Una grabacion por material. La salida usa la misma muestra mas floja: es
    # el mismo material rompiendose por el otro lado, no otro sonido.
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
            sound_name = "impact_drywall"
            volume = -5.0
        "flesh":
            sound_name = "impact_flesh"
        _:
            sound_name = "impact_concrete"
    if is_exit:
        volume -= 3.0
    GameAudio.play_3d(sound_name, point, volume, randf_range(0.92, 1.08))


func spawn_muzzle_smoke(point: Vector3, direction: Vector3) -> void:
    var pm := ParticleProcessMaterial.new()
    pm.direction = direction.normalized()
    pm.spread = 24.0
    pm.initial_velocity_min = 0.25
    pm.initial_velocity_max = 0.9
    # El humo acompana al disparo hacia delante y se disipa: antes subia
    # demasiado (+0.35) durante 0.9 s y desde atras se leia como una estela
    # vertical colgando sobre la corredera.
    pm.gravity = Vector3(0, 0.12, 0)
    pm.scale_min = 0.45
    pm.scale_max = 1.8
    pm.color = Color(0.55, 0.55, 0.52, 0.24)
    pm.damping_min = 1.6
    pm.damping_max = 2.4

    var particles := GPUParticles3D.new()
    particles.amount = 7
    particles.lifetime = 0.6
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.process_material = pm
    particles.draw_pass_1 = _particle_quad(SOFT_TEXTURE, Color(0.6, 0.6, 0.58, 0.28), false, Vector2(0.055, 0.055))
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(particles)
    particles.global_position = point
    get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


## Agujero del impacto: geometria OPACA, no una calcomania con alfa.
##
## El Decal nativo no dibuja en el renderer Mobile sobre GL, y el alfa de la
## textura del agujero no llega al fragmento (sale un cuadrado negro). Lo que si
## funciona y ademas da profundidad es tallar el agujero: un embudo de dos
## anillos con el interior hundido y un labio que sobresale una decima de
## milimetro. El interior es oscuro y sin shading (es un hueco, no una
## superficie iluminada); el labio si recibe luz. Nada de esto depende de alfa.
func _spawn_decal(point: Vector3, normal: Vector3, collider: Object, surface: String, is_exit: bool) -> void:
    var profile: Dictionary = IMPACT_MATERIALS.get(surface, IMPACT_MATERIALS["concrete"])
    var size := float(HOLE_SIZE.get(surface, 0.026))
    if is_exit:
        size *= float(profile.get("exit_scale", 1.35))

    var n := normal.normalized()
    if n.length_squared() < 0.01:
        n = Vector3.UP
    var basis := _surface_basis(n).rotated(n, randf_range(0.0, TAU))

    var hole := MeshInstance3D.new()
    hole.name = "BulletHole"
    hole.mesh = _hole_mesh(size, surface, is_exit)
    hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(hole)
    hole.global_transform = Transform3D(basis, point)

    if collider is Node3D and collider.get_meta("dynamic_decal", false):
        hole.reparent(collider, true)

    _holes.append(hole)
    if _holes.size() > MAX_HOLES:
        var old: Node = _holes.pop_front()
        if is_instance_valid(old):
            old.queue_free()


## Embudo del agujero en el plano XY local (Z = normal). `size` es el diametro
## exterior: el interior es ~30% de eso y esta hundido; el labio sobresale para
## que la luz marque el borde. La salida es mas ancha y casi plana.
func _hole_mesh(size: float, surface: String, is_exit: bool) -> ArrayMesh:
    var segments := 8
    var lip := size * 0.5
    var inner := size * 0.34
    # Profundidad: la salida revienta hacia fuera (casi plana); la entrada se
    # hunde segun el material. El metal no se hunde: marca y ya.
    var depth := 0.0012
    var bulge := -0.0004
    if not is_exit:
        depth = float(IMPACT_MATERIALS.get(surface, {}).get("crater", 0.004))
    else:
        bulge = 0.0008

    var verts := PackedVector3Array()
    var idx := PackedInt32Array()
    # Centro hundido, anillo interior irregular y labio en la superficie.
    verts.append(Vector3(0.0, 0.0, bulge - depth))
    for i in range(segments):
        var a := TAU * float(i) / float(segments)
        var r := inner * (0.80 + randf() * 0.45)
        verts.append(Vector3(cos(a) * r, sin(a) * r, bulge - depth * 0.45))
    for i in range(segments):
        var a := TAU * float(i) / float(segments)
        var r := lip * (0.86 + randf() * 0.28)
        verts.append(Vector3(cos(a) * r, sin(a) * r, bulge))
    var inner_start := 1
    var outer_start := 1 + segments
    for i in range(segments):
        var j := (i + 1) % segments
        idx.append(0); idx.append(inner_start + j); idx.append(inner_start + i)
        idx.append(inner_start + i); idx.append(inner_start + j); idx.append(outer_start + j)
        idx.append(inner_start + i); idx.append(outer_start + j); idx.append(outer_start + i)

    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = verts
    arrays[Mesh.ARRAY_INDEX] = idx
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    # Interior del agujero: un hueco, no una superficie; nada de shading y casi
    # negro. El material solo define el tono de lo que se ha roto.
    var mat := StandardMaterial3D.new()
    if surface == "wood":
        mat.albedo_color = Color(0.09, 0.06, 0.03)
    elif surface == "drywall":
        mat.albedo_color = Color(0.13, 0.12, 0.11)
    elif surface == "metal":
        mat.albedo_color = Color(0.10, 0.10, 0.11)
        mat.metallic = 0.6
        mat.roughness = 0.35
    elif surface == "paper":
        mat.albedo_color = Color(0.10, 0.09, 0.08)
    else:
        mat.albedo_color = Color(0.03, 0.03, 0.028)
    mat.roughness = 1.0
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.disable_receive_shadows = true
    mesh.surface_set_material(0, mat)
    return mesh


## Base con la normal como eje Z, para apoyar Decal y crater en la superficie.
func _surface_basis(n: Vector3) -> Basis:
    var up_ref := Vector3.UP
    if absf(n.dot(up_ref)) > 0.94:
        up_ref = Vector3.RIGHT
    var x_axis := up_ref.cross(n).normalized()
    if x_axis.length_squared() < 0.01:
        x_axis = Vector3.RIGHT
    var y_axis := n.cross(x_axis).normalized()
    if y_axis.length_squared() < 0.01:
        y_axis = Vector3.FORWARD
    return Basis(x_axis, y_axis, n)


## Respuesta por material. Cada entrada declara una o dos eyecciones DISTINTAS:
##   dust   - lo que queda en el aire (polvo mineral, yeso, fibra fina)
##   debris - lo que sale disparado y cae (esquirlas, astillas, chispas)
## No son las mismas particulas con otro color: cambian cantidad, velocidad,
## gravedad, tamano, duracion y textura. El papel casi no se mueve; el hormigon
## levanta polvo y esquirlas; la madera, astillas alargadas; el metal, chispas
## con luz. `crater` es la profundidad del reborde de entrada en metros (0 = no
## se rompe hacia dentro, como el metal o el papel).
const IMPACT_MATERIALS := {
    "concrete": {
        "dust": {"amount": 9, "color": Color(0.56, 0.55, 0.52, 0.60), "vel": [0.4, 1.6], "gravity": -2.0, "scale": [0.6, 2.4], "life": 0.85, "size": 0.050, "spread": 62.0},
        "debris": {"amount": 6, "color": Color(0.34, 0.33, 0.31, 0.95), "vel": [2.6, 6.5], "gravity": -13.0, "scale": [0.18, 0.50], "life": 0.50, "size": 0.018, "spread": 70.0},
        "exit_scale": 1.25,
        "crater": 0.0045,
    },
    "drywall": {
        "dust": {"amount": 14, "color": Color(0.82, 0.80, 0.75, 0.72), "vel": [0.5, 2.0], "gravity": -1.4, "scale": [0.8, 3.0], "life": 1.05, "size": 0.058, "spread": 74.0},
        "debris": {"amount": 4, "color": Color(0.72, 0.70, 0.64, 0.90), "vel": [1.8, 4.4], "gravity": -8.0, "scale": [0.30, 0.80], "life": 0.60, "size": 0.026, "spread": 66.0},
        "exit_scale": 1.80,
        "crater": 0.0035,
    },
    "wood": {
        "dust": {"amount": 7, "color": Color(0.46, 0.33, 0.18, 0.62), "vel": [0.5, 2.0], "gravity": -2.6, "scale": [0.5, 1.8], "life": 0.70, "size": 0.044, "spread": 60.0},
        "debris": {"amount": 8, "color": Color(0.35, 0.22, 0.10, 0.98), "vel": [3.4, 8.0], "gravity": -12.0, "scale": [0.30, 0.85], "life": 0.60, "size": 0.030, "spread": 52.0, "stretch": 4.0},
        "exit_scale": 1.50,
        "crater": 0.0050,
    },
    "metal": {
        "debris": {"amount": 18, "color": Color(1.0, 0.72, 0.26, 1.0), "vel": [3.0, 8.0], "gravity": -11.0, "scale": [0.30, 1.10], "life": 0.34, "size": 0.018, "spread": 58.0, "spark": true},
        "dust": {"amount": 5, "color": Color(0.50, 0.50, 0.52, 0.35), "vel": [0.4, 1.4], "gravity": -2.0, "scale": [0.40, 1.20], "life": 0.40, "size": 0.030, "spread": 50.0},
        "exit_scale": 1.15,
        "crater": 0.0,
    },
    "paper": {
        "dust": {"amount": 4, "color": Color(0.84, 0.81, 0.74, 0.50), "vel": [0.2, 0.8], "gravity": -1.0, "scale": [0.30, 0.90], "life": 0.35, "size": 0.020, "spread": 44.0},
        "exit_scale": 1.10,
        "crater": 0.0,
    },
    "flesh": {
        "dust": {"amount": 6, "color": Color(0.42, 0.12, 0.10, 0.55), "vel": [0.4, 1.6], "gravity": -2.2, "scale": [0.4, 1.4], "life": 0.45, "size": 0.034, "spread": 58.0},
        "exit_scale": 1.0,
        "crater": 0.0,
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
