extends Node3D

## Presentacion de impactos y penetracion. NO decide balistica: Ballistics.gd
## dice DONDE entra/sale y CONTRA QUE; aqui solo se representa el material roto.
##
## Un impacto legible tiene tres capas distintas:
##   1. cavidad oscura: pequena y hundida; es profundidad, no una pegatina negra
##   2. labio fracturado: material expuesto que SI recibe luz
##   3. eyeccion: polvo/astillas/chispas segun el material y si es entrada/salida
##
## Entrada y salida no son el mismo agujero escalado. La salida abre mas el
## material, tiene borde mas irregular y expulsa masa hacia fuera.

const SOFT_TEXTURE: Texture2D = preload("res://assets/textures/particle_soft.png")
const SPARK_TEXTURE: Texture2D = preload("res://assets/textures/particle_spark.png")

const MAX_HOLES := 128
const HOLE_SIZE := {
    "concrete": 0.070,
    "drywall": 0.064,
    "wood": 0.064,
    "metal": 0.048,
    "paper": 0.040,
}

var _holes: Array[Node] = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS


func spawn_impact(point: Vector3, normal: Vector3, collider: Object, surface: String, is_exit: bool = false) -> void:
    _spawn_decal(point, normal, collider, surface, is_exit)
    _spawn_particles(point, normal, surface, is_exit)
    if not is_exit:
        _spawn_light(point, surface)

    # En una lamina/tabla la entrada y la salida suceden con separacion de
    # milisegundos. Reproducir la misma muestra DOS veces hacia que una sola
    # penetracion sonara como dos impactos baratos. El evento acustico se oye
    # en la entrada; la salida se comunica con geometria y eyeccion.
    if is_exit:
        return

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
        _:
            sound_name = "impact_concrete"
    GameAudio.play_3d(sound_name, point, volume, randf_range(0.92, 1.08))


func spawn_muzzle_smoke(point: Vector3, direction: Vector3) -> void:
    var pm := ParticleProcessMaterial.new()
    pm.direction = direction.normalized()
    pm.spread = 24.0
    pm.initial_velocity_min = 0.25
    pm.initial_velocity_max = 0.9
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


## Agujero de dos superficies. Antes TODO el embudo usaba un unico material
## casi negro y el radio interior era enorme: desde camara se leia como una
## moneda negra pegada a la pared. Ahora solo la cavidad central es oscura; el
## anillo roto conserva el color del material y recibe iluminacion.
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
    hole.name = "BulletExit" if is_exit else "BulletEntry"
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


## Construye una cavidad pequena + un labio de fractura ancho. La entrada es
## mas profunda y contenida; la salida es mas plana, abierta e irregular.
func _hole_mesh(size: float, surface: String, is_exit: bool) -> ArrayMesh:
    const SEGMENTS := 10
    var outer_radius := size * 0.5
    var inner_radius := size * (0.22 if is_exit else 0.17)
    var profile: Dictionary = IMPACT_MATERIALS.get(surface, IMPACT_MATERIALS["concrete"])
    var depth := 0.0010 if is_exit else float(profile.get("crater", 0.0035))
    var bulge := 0.0011 if is_exit else 0.00055

    var verts := PackedVector3Array()
    var cavity_idx := PackedInt32Array()
    var lip_idx := PackedInt32Array()

    # Centro real del hueco.
    verts.append(Vector3(0.0, 0.0, bulge - depth))

    # Anillo interior. La salida rompe mas desigual que la entrada.
    for i in range(SEGMENTS):
        var a := TAU * float(i) / float(SEGMENTS)
        var jitter := randf_range(0.72, 1.32) if is_exit else randf_range(0.82, 1.20)
        var r := inner_radius * jitter
        var z := bulge - depth * randf_range(0.34, 0.58)
        verts.append(Vector3(cos(a) * r, sin(a) * r, z))

    # Labio exterior roto. No es circular: cada sector conserva una longitud
    # diferente y la salida tiene mas desgarro radial.
    for i in range(SEGMENTS):
        var a := TAU * float(i) / float(SEGMENTS)
        var jitter := randf_range(0.72, 1.30) if is_exit else randf_range(0.84, 1.18)
        var r := outer_radius * jitter
        var z := bulge + (randf_range(-0.00020, 0.00038) if is_exit else randf_range(-0.00010, 0.00018))
        verts.append(Vector3(cos(a) * r, sin(a) * r, z))

    var inner_start := 1
    var outer_start := 1 + SEGMENTS
    for i in range(SEGMENTS):
        var j := (i + 1) % SEGMENTS
        # Cavidad: solo centro -> anillo interior.
        cavity_idx.append(0)
        cavity_idx.append(inner_start + j)
        cavity_idx.append(inner_start + i)
        # Fractura: anillo interior -> borde exterior.
        lip_idx.append(inner_start + i)
        lip_idx.append(inner_start + j)
        lip_idx.append(outer_start + j)
        lip_idx.append(inner_start + i)
        lip_idx.append(outer_start + j)
        lip_idx.append(outer_start + i)

    var cavity_arrays := []
    cavity_arrays.resize(Mesh.ARRAY_MAX)
    cavity_arrays[Mesh.ARRAY_VERTEX] = verts
    cavity_arrays[Mesh.ARRAY_INDEX] = cavity_idx

    var lip_arrays := []
    lip_arrays.resize(Mesh.ARRAY_MAX)
    lip_arrays[Mesh.ARRAY_VERTEX] = verts
    lip_arrays[Mesh.ARRAY_INDEX] = lip_idx

    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cavity_arrays)
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lip_arrays)
    mesh.surface_set_material(0, _cavity_material(surface))
    mesh.surface_set_material(1, _fracture_material(surface, is_exit))
    return mesh


func _cavity_material(surface: String) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    match surface:
        "wood":
            mat.albedo_color = Color(0.050, 0.031, 0.015)
        "drywall":
            mat.albedo_color = Color(0.085, 0.080, 0.072)
        "metal":
            mat.albedo_color = Color(0.055, 0.058, 0.064)
            mat.metallic = 0.75
            mat.roughness = 0.34
        "paper":
            mat.albedo_color = Color(0.075, 0.066, 0.055)
        _:
            mat.albedo_color = Color(0.024, 0.024, 0.022)
    mat.roughness = 1.0 if surface != "metal" else mat.roughness
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.disable_receive_shadows = true
    return mat


func _fracture_material(surface: String, is_exit: bool) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    match surface:
        "wood":
            # Fibra fresca: mucho mas clara que el agujero carbonizado anterior.
            mat.albedo_color = Color(0.46, 0.30, 0.14)
            mat.roughness = 0.96
        "drywall":
            mat.albedo_color = Color(0.74, 0.71, 0.65)
            mat.roughness = 1.0
        "metal":
            mat.albedo_color = Color(0.32, 0.33, 0.36)
            mat.metallic = 0.82
            mat.roughness = 0.30
        "paper":
            mat.albedo_color = Color(0.70, 0.66, 0.56)
            mat.roughness = 1.0
        _:
            mat.albedo_color = Color(0.38, 0.37, 0.34)
            mat.roughness = 0.95
    if is_exit:
        # Cara rota expuesta a la luz: un poco mas clara, sin volverla blanca.
        var c := mat.albedo_color
        mat.albedo_color = Color(minf(c.r * 1.12, 1.0), minf(c.g * 1.12, 1.0), minf(c.b * 1.12, 1.0), c.a)
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mat


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


## Respuesta por material. Polvo y fragmento NO son la misma particula pintada:
## cambian cantidad, velocidad, gravedad, tamano, duracion y silueta.
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
        "exit_scale": 1.60,
        "crater": 0.0,
    },
}


func _spawn_particles(point: Vector3, normal: Vector3, surface: String, is_exit: bool) -> void:
    var profile: Dictionary = IMPACT_MATERIALS.get(surface, IMPACT_MATERIALS["concrete"])
    var n := normal.normalized()
    var strength := 1.0
    if is_exit:
        # La salida no es "la entrada al 55%". Madera/yeso arrancan material
        # hacia fuera; hormigon/papel pierden menos masa visible.
        match surface:
            "drywall":
                strength = 1.35
            "wood":
                strength = 1.15
            "paper":
                strength = 0.75
            "concrete":
                strength = 0.78
            _:
                strength = 0.65
    for key in ["dust", "debris"]:
        if profile.has(key):
            _burst(point + n * 0.006, n, profile[key], strength)


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
    particles.amount = maxi(1, int(round(amount * (1.0 if strength >= 1.0 else 0.72 + 0.28 * strength))))
    particles.lifetime = float(spec["life"])
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.process_material = pm
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