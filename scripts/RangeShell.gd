extends Node3D
## RangeShell: la arquitectura del rango es GEOMETRIA y solo geometria.
##
## El .glb NO lleva texturas dentro. `tools/build_range_shell.py` exporta la
## malla con UV a densidad fisica (una vuelta de textura cada N metros de
## mundo) y el nombre de material; aqui se enganchan los mapas PBR que ya viven
## en `assets/textures/real/`, que son la UNICA fuente de esas imagenes.
##
## Por que asi: antes el .glb pesaba 9,77 MB porque embebia 12 imagenes, seis de
## ellas copias byte a byte de las del repo. Ahora el .glb son 2,8 MB de
## geometria pura y no hay ni un byte de textura duplicado.
##
## El material de cada grupo trae escrita la escala con la que se construyo su
## UV (`metros_por_tile`), asi que aqui no se recalibra nada: se sustituye el
## mapa y se deja el UV como vino.

## Nombre del MATERIAL del .glb -> mapas del repo. Las claves son exactamente
## los nombres que exporta `tools/build_range_shell.py` (si no coinciden, el
## enganche falla en silencio y la sala se dibuja con color plano). Los tres canales son albedo / roughness /
## normal. La escala de UV NO se toca: viaja horneada en la malla.
const MAPS := {
    "Range_Concrete_Floor": {
        "albedo": "res://assets/textures/real/concrete_brushed_concrete_diff.jpg",
        "rough": "res://assets/textures/real/concrete_brushed_concrete_rough.jpg",
        "normal": "res://assets/textures/real/concrete_brushed_concrete_nor_gl.jpg",
        "color": Color(0.74, 0.73, 0.72),
        "metallic": 0.0,
        "roughness": 0.93,
        "normal_scale": 0.28,
    },
    "Range_Concrete_Brushed": {
        "albedo": "res://assets/textures/real/concrete_brushed_concrete_diff.jpg",
        "rough": "res://assets/textures/real/concrete_brushed_concrete_rough.jpg",
        "normal": "res://assets/textures/real/concrete_brushed_concrete_nor_gl.jpg",
        "color": Color(0.78, 0.77, 0.75),
        "metallic": 0.0,
        "roughness": 0.86,
        "normal_scale": 0.30,
    },
    "Range_Concrete_Wall": {
        "albedo": "res://assets/textures/real/concrete_concrete_diff.jpg",
        "rough": "res://assets/textures/real/concrete_concrete_rough.jpg",
        "normal": "res://assets/textures/real/concrete_concrete_nor_gl.jpg",
        "color": Color(0.76, 0.76, 0.78),
        "metallic": 0.0,
        "roughness": 0.90,
        "normal_scale": 0.35,
    },
    "Range_Painted_Metal": {
        "albedo": "res://assets/textures/real/metal_metal_plate_diff.jpg",
        "rough": "res://assets/textures/real/metal_metal_plate_rough.jpg",
        "normal": "res://assets/textures/real/metal_metal_plate_nor_gl.jpg",
        "color": Color(0.30, 0.32, 0.35),
        "metallic": 0.55,
        "roughness": 0.48,
        "normal_scale": 0.55,
    },
    "Range_Oak_Trim": {
        "albedo": "res://assets/textures/real/wood_oak_wood_planks_diff.jpg",
        "rough": "res://assets/textures/real/wood_oak_wood_planks_rough.jpg",
        "normal": "res://assets/textures/real/wood_oak_wood_planks_nor_gl.jpg",
        "color": Color(0.62, 0.50, 0.37),
        "metallic": 0.0,
        "roughness": 0.84,
        "normal_scale": 0.75,
    },
    "Range_Markings": {
        "albedo": "",
        "rough": "",
        "normal": "",
        "color": Color(0.64, 0.57, 0.40),
        "metallic": 0.0,
        "roughness": 0.88,
    },
}

## El difusor de las luminarias es la unica superficie emisiva del shell. Las
## luces reales viven en la escena (`Lighting`), que es quien decide cuantas
## hay y cuales proyectan sombra.
const LUMINAIRE_MATERIAL := "Range_Luminaire"

var _cache: Dictionary = {}


func _ready() -> void:
    _rebind(find_children("*", "MeshInstance3D", true, false))
    var lighting := get_node_or_null("Lighting")
    if lighting != null:
        for light in lighting.find_children("*", "Light3D", true, false):
            (light as Light3D).light_cull_mask = 4095


func _rebind(nodes: Array) -> void:
    var rebound := 0
    for node in nodes:
        var mi := node as MeshInstance3D
        if mi == null or mi.mesh == null:
            continue
        var key := ""
        for surface in range(mi.mesh.get_surface_count()):
            var source := mi.mesh.surface_get_material(surface)
            if source != null and source.resource_name != "":
                key = source.resource_name
                break
        var mat := _material(key)
        if mat != null:
            mi.material_override = mat
            rebound += 1
    print("RANGE shell: %d mallas con texturas externas del repo" % rebound)


func _material(group: String) -> Material:
    if _cache.has(group):
        return _cache[group]
    var mat: Material = null
    if group == LUMINAIRE_MATERIAL:
        mat = _luminaire()
    elif MAPS.has(group):
        mat = _pbr(MAPS[group])
    if mat != null:
        mat.resource_name = group
        _cache[group] = mat
    return mat


func _pbr(spec: Dictionary) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = spec["color"]
    mat.metallic = spec["metallic"]
    mat.roughness = spec["roughness"]
    if spec["albedo"] != "":
        mat.albedo_texture = load(spec["albedo"])
    if spec["rough"] != "":
        mat.roughness_texture = load(spec["rough"])
    if spec["normal"] != "":
        mat.normal_enabled = true
        mat.normal_texture = load(spec["normal"])
        mat.normal_scale = spec.get("normal_scale", 0.6)
    mat.uv1_scale = Vector3.ONE
    return mat


func _luminaire() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.92, 0.90, 0.84)
    mat.roughness = 0.28
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.93, 0.76)
    mat.emission_energy_multiplier = 0.9
    return mat
