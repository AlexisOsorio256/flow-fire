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
##
## EL AGUJERO ES UN `Decal` NATIVO, no una malla. Godot lo proyecta sobre lo que
## tenga debajo (funciona en el renderer Mobile), asi que el agujero se adapta a
## una pared, a un bidon curvado o a una lata sin fabricar geometria por impacto:
## antes eran ~90 lineas de malla procedural por agujero y el borde tenia que
## inventarse el relieve. Lo unico que se genera aqui son CINCO siluetas (una por
## material) UNA vez al arrancar, con el hundimiento, el labio y el color ya
## cocidos dentro.
##
## DOS TRAMPAS DEL MOTOR QUE COSTARON SANGRE, no repetirlas:
##   1. La caja de proyeccion es [0,1]x[-1,1]x[0,1] en local y el shader
##      DESCARTA el fragmento que cae justo en el borde. Si la superficie
##      coincide con el limite de la caja, el agujero no sale (o sale a rayas):
##      de ahi `PROJECTION_MARGIN`.
##   2. Godot solo aplica OCHO decales por malla (`sc_decals(8)`), asi que dos
##      decales por agujero dejaban una pared con cuatro agujeros y el motor
##      elegia cuales. Un decal por agujero + `HOLES_PER_SURFACE` para que los
##      que se vean sean siempre los ultimos.
##
## Las particulas (polvo, astillas, chispas) siguen siendo `GPUParticles3D`.

const SOFT_TEXTURE: Texture2D = preload("res://assets/textures/particle_soft.png")
const SPARK_TEXTURE: Texture2D = preload("res://assets/textures/particle_spark.png")

## Tope de agujeros vivos en toda la escena. Tambien hay tope POR OBJETO: ver
## `HOLES_PER_SURFACE`.
const MAX_HOLES := 128
## El motor solo proyecta 8 decales por malla; de aqui para arriba el agujero
## mas viejo de esa superficie se borra para que el ultimo disparo se vea.
const HOLES_PER_SURFACE := 8
const HOLE_SIZE := {
    "concrete": 0.070,
    "drywall": 0.064,
    "wood": 0.064,
    "metal": 0.048,
    "aluminum": 0.042,
    "paper": 0.040,
}

## Color de la cavidad y del labio, por material. Se cuecen dentro de la
## silueta: el `Decal` va con `modulate` blanco para no gastar dos decales.
const CAVITY_TINT := {
    "concrete": Color(0.024, 0.024, 0.022),
    "drywall": Color(0.085, 0.080, 0.072),
    "wood": Color(0.050, 0.031, 0.015),
    "metal": Color(0.055, 0.058, 0.064),
    "aluminum": Color(0.62, 0.63, 0.65),
    "paper": Color(0.075, 0.066, 0.055),
}
const LIP_TINT := {
    "concrete": Color(0.38, 0.37, 0.34),
    "drywall": Color(0.74, 0.71, 0.65),
    "wood": Color(0.46, 0.30, 0.14),
    "metal": Color(0.32, 0.33, 0.36),
    "aluminum": Color(0.78, 0.79, 0.81),
    "paper": Color(0.70, 0.66, 0.56),
}
## Lado de la textura de silueta. 96 px sobra para un agujero de 5 cm.
const MASK_SIZE := 96
## Caja de proyeccion del decal: fondo suficiente para atravesar la chapa de una
## lata (0,12 mm) y quedarse corto para no manchar lo de mas atras.
const DECAL_DEPTH := 0.03
## Holgura entre la superficie y el borde de la caja de proyeccion. Godot
## descarta el fragmento que caiga EN el borde de la caja, asi que con la
## superficie justo en el limite el agujero no se dibuja (o sale a rayas).
const PROJECTION_MARGIN := 0.003

## Agujeros vivos: cada entrada lleva el nodo y la superficie (objeto) sobre la
## que esta proyectado. El objeto se guarda aqui y no en `meta` del nodo porque
## `set_meta` con valor nulo no guarda nada y luego `get_meta` suelta un error.
var _holes: Array[Dictionary] = []
var _masks := {}


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    for surface in IMPACT_MATERIALS:
        _masks[surface] = _make_hole_texture(surface)


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
        "aluminum":
            sound_name = "impact_metal"
            volume = -6.0
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


## Humo de boca: una voluta palida que se lee contra el fondo negro del rango.
## CALIBRADO: el gris 0.55 a alfa 0.24 no se veia en juego; 0.72/0.42 si, sin
## parecer humo de pelicula (9 particulas, 0.9 s, a la deriva).
func spawn_muzzle_smoke(point: Vector3, direction: Vector3) -> void:
    var pm := ParticleProcessMaterial.new()
    pm.direction = direction.normalized()
    pm.spread = 24.0
    pm.initial_velocity_min = 0.2
    pm.initial_velocity_max = 0.6
    pm.gravity = Vector3(0, 0.12, 0)
    pm.scale_min = 0.45
    pm.scale_max = 1.8
    pm.color = Color(0.72, 0.72, 0.70, 0.38)
    pm.damping_min = 1.6
    pm.damping_max = 2.4

    var particles := GPUParticles3D.new()
    particles.amount = 9
    particles.lifetime = 0.9
    particles.one_shot = true
    particles.explosiveness = 1.0
    particles.process_material = pm
    particles.draw_pass_1 = _particle_quad(SOFT_TEXTURE, Color(0.75, 0.75, 0.73, 0.42), false, Vector2(0.075, 0.075))
    particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(particles)
    particles.global_position = point
    get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


## Agujero de bala: UN `Decal` anclado a la superficie, con la cavidad hundida
## y el labio de material roto en la misma silueta. El que proyecta es Godot;
## aqui solo se eligen tamano y colocacion de la caja de proyeccion.
func _spawn_decal(point: Vector3, normal: Vector3, collider: Object, surface: String, is_exit: bool) -> void:
    var profile: Dictionary = IMPACT_MATERIALS.get(surface, IMPACT_MATERIALS["concrete"])
    var size := float(HOLE_SIZE.get(surface, 0.030))
    if is_exit:
        size *= float(profile.get("exit_scale", 1.35))

    var n := normal.normalized()
    if n.length_squared() < 0.01:
        n = Vector3.UP

    var holder := Node3D.new()
    holder.name = "BulletExit" if is_exit else "BulletEntry"
    add_child(holder)
    ## La caja de proyeccion tiene que CONTENER la superficie con holgura: se
    ## deja casi toda dentro del material y solo los 3 mm de fuera que evitan
    ## que el borde de la caja coincida con la cara (ver PROJECTION_MARGIN).
    var basis := _decal_basis(n).rotated(n, randf_range(0.0, TAU))
    holder.global_transform = Transform3D(basis,
        point - n * (DECAL_DEPTH * 0.5 - PROJECTION_MARGIN))

    _add_decal(holder, _masks.get(surface, _masks["concrete"]), size)

    if collider is Node3D and collider.get_meta("dynamic_decal", false):
        holder.reparent(collider, true)

    _holes.append({"holder": holder, "surface": collider})
    _evict(collider)


## Un `Decal` con su silueta y su tamano. El decal proyecta a lo largo de su Y,
## asi que la base que le llega ya tiene la normal en la Y.
func _add_decal(parent: Node3D, mask: Texture2D, footprint: float) -> void:
    var decal := Decal.new()
    decal.texture_albedo = mask
    decal.size = Vector3(footprint, DECAL_DEPTH, footprint)
    decal.upper_fade = 0.0
    decal.lower_fade = 0.35
    ## 0,45 de normal_fade: en una pared perpendicular el decal se apaga en vez
    ## de estirarse por el canto.
    decal.normal_fade = 0.45
    decal.distance_fade_enabled = true
    decal.distance_fade_begin = 9.0
    decal.distance_fade_length = 5.0
    parent.add_child(decal)


## Godot elige por su cuenta los 8 decales que aplica a una malla, y no siempre
## son los ultimos. Aqui se mantiene el cupo por objeto para que lo que se vea
## sea siempre el disparo reciente: el agujero viejo se borra al llegar al tope.
func _evict(collider: Object) -> void:
    var same: Array[Dictionary] = []
    for hole in _holes:
        if is_instance_valid(hole["holder"]) and hole["surface"] == collider:
            same.append(hole)
    while same.size() > HOLES_PER_SURFACE:
        _drop(same.pop_front())
    while _holes.size() > MAX_HOLES:
        _drop(_holes.pop_front())


func _drop(hole: Dictionary) -> void:
    _holes.erase(hole)
    var node: Node = hole["holder"]
    if is_instance_valid(node):
        node.queue_free()


## Base para proyectar sobre una superficie plana o curva.
func _decal_basis(n: Vector3) -> Basis:
    var up := Vector3.UP
    if absf(n.dot(up)) > 0.94:
        up = Vector3.RIGHT
    var x_axis := up.cross(n).normalized()
    if x_axis.length_squared() < 0.01:
        x_axis = Vector3.RIGHT
    var z_axis := x_axis.cross(n).normalized()
    return Basis(x_axis, n, z_axis)


## Silueta del agujero, generada UNA vez al arrancar por material: en el mismo
## RGBA va el hundimiento oscuro del centro, el labio de material roto pegado al
## canto y el color de cada zona ya cocido (el decal va sin `modulate`). Un solo
## decal por agujero porque el motor solo proyecta ocho por malla.
func _make_hole_texture(surface: String) -> ImageTexture:
    var cavity: Color = CAVITY_TINT.get(surface, CAVITY_TINT["concrete"])
    var lip: Color = LIP_TINT.get(surface, LIP_TINT["concrete"])
    var img := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGBA8)
    for y in range(MASK_SIZE):
        for x in range(MASK_SIZE):
            var u := (float(x) + 0.5) / float(MASK_SIZE) * 2.0 - 1.0
            var v := (float(y) + 0.5) / float(MASK_SIZE) * 2.0 - 1.0
            var r := sqrt(u * u + v * v)
            var angle := atan2(v, u)
            ## Ruido atado al ANGULO: el borde se rompe, no se ensucia el centro.
            var noise := _fbm(cos(angle) * 3.1 + 5.0, sin(angle) * 3.1 + 5.0)
            ## Canto del agujero: corto (0,10 de radio). Con un desvanecido ancho
            ## el disco entero se apagaba y el impacto se leia como una mancha.
            var edge := 0.36 * (1.0 + 0.18 * (noise - 0.5))
            var hole := smoothstep(edge, edge - 0.10, r)
            ## El centro se hunde: casi negro en el fondo, color del material en
            ## el canto.
            var depth := 0.24 + 0.76 * smoothstep(0.0, maxf(edge, 0.01), r)
            ## Labio: pegado al canto y medio transparente, para que la textura
            ## de debajo (madera, metal) siga leyendose a traves del material
            ## arrancado. Sin anillo de pared limpia en medio.
            var outer := 0.62 * (1.0 + 0.16 * (noise - 0.5))
            var chipped := smoothstep(edge - 0.05, edge + 0.02, r) \
                * (1.0 - smoothstep(outer - 0.07, outer, r))
            var alpha := maxf(hole, chipped * 0.62)
            var color := (lip * (0.72 + 0.28 * noise)).lerp(cavity * depth, hole)
            img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0)))
    return ImageTexture.create_from_image(img)


## Ruido de valor barato y DETERMINISTA: la silueta es la misma en cada partida,
## asi que dos agujeros del mismo material no salen distintos porque si.
static func _fbm(x: float, y: float) -> float:
    return _value_noise(x, y) * 0.65 + _value_noise(x * 2.7 + 11.3, y * 2.7 + 7.1) * 0.35


static func _value_noise(x: float, y: float) -> float:
    var xi := floori(x)
    var yi := floori(y)
    var xf := x - float(xi)
    var yf := y - float(yi)
    var sx := xf * xf * (3.0 - 2.0 * xf)
    var sy := yf * yf * (3.0 - 2.0 * yf)
    var a := _hash01(xi, yi)
    var b := _hash01(xi + 1, yi)
    var c := _hash01(xi, yi + 1)
    var d := _hash01(xi + 1, yi + 1)
    return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


static func _hash01(a: int, b: int) -> float:
    var h := (a * 374761393 + b * 668265263) ^ 0x5BF03635
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return float(h & 0xFFFFFF) / float(0xFFFFFF)


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
    "aluminum": {
        "debris": {"amount": 4, "color": Color(1.0, 0.80, 0.40, 1.0), "vel": [2.0, 5.0], "gravity": -11.0, "scale": [0.30, 0.90], "life": 0.22, "size": 0.012, "spread": 50.0, "spark": true},
        "dust": {"amount": 3, "color": Color(0.70, 0.71, 0.72, 0.30), "vel": [0.3, 1.0], "gravity": -2.0, "scale": [0.30, 0.90], "life": 0.30, "size": 0.022, "spread": 44.0},
        "exit_scale": 1.25,
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
    if surface != "metal" and surface != "aluminum":
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