class_name GunMaterials
extends RefCounted

## Materiales del arma, indexados por el NOMBRE de la primitiva del GLB.
##
## El modelo trae 9 primitivas con nombres (Frame, Black, Slide, White,
## GrayShade2, Magazine, BulletCasing, BulletCasing2, BulletTip) y ninguna
## textura. Asignar por nombre evita el error de antes: por índice, la mira
## ("White") y la primitiva más grande ("GrayShade2") acababan con material de
## acero y el arma se veía como un bloque negro.
##
## Los valores base salen de los del propio GLB, subidos donde la escena los
## dejaba ilegibles (interior oscuro, metal sin reflejos = negro).

const SHADER: Shader = preload("res://shaders/gun.gdshader")


static func build() -> Dictionary:
    return {
        # Armazón de polímero: sin metal, rugoso y con picado.
        "Frame": _make(Color(0.082, 0.083, 0.088), 0.04, 0.70, {
            "detail_scale": 220.0, "stipple": 0.9, "detail_albedo": 0.10, "wear": 0.10,
        }),
        # Piezas negras (gatillo, seguros, piezas internas).
        "Black": _make(Color(0.038, 0.038, 0.042), 0.30, 0.50, {
            "detail_scale": 260.0, "wear": 0.15,
        }),
        # Corredera: acero pavonado, rayado de mecanizado y roce en los cantos.
        "Slide": _make(Color(0.105, 0.11, 0.12), 0.70, 0.34, {
            "detail_scale": 200.0, "streak": 0.55, "detail_roughness": 0.14, "wear": 0.30,
        }),
        # Puntos y contorno de la mira: blancos, con un punto de emisión.
        "White": _make(Color(0.82, 0.83, 0.85), 0.0, 0.35, {
            "detail_scale": 300.0, "wear": 0.0, "emission_color": Color(0.35, 0.36, 0.38),
            "emission_energy": 0.15,
        }),
        # Piezas grises (cañón, guía de muelle, extractor).
        "GrayShade2": _make(Color(0.135, 0.14, 0.155), 0.75, 0.30, {
            "detail_scale": 190.0, "streak": 0.35, "wear": 0.22,
        }),
        # Cargador: cuerpo de polímero con la boca metálica.
        "Magazine": _make(Color(0.075, 0.076, 0.082), 0.20, 0.58, {
            "detail_scale": 200.0, "stipple": 0.5, "wear": 0.15,
        }),
        # Cartuchos (los usa el cargador y la bala que se oculta).
        "BulletCasing": _make(Color(0.62, 0.45, 0.17), 0.95, 0.24, {
            "detail_scale": 260.0, "wear": 0.2,
        }),
        "BulletCasing2": _make(Color(0.52, 0.34, 0.12), 0.95, 0.28, {
            "detail_scale": 260.0, "wear": 0.2,
        }),
        "BulletTip": _make(Color(0.45, 0.19, 0.08), 0.75, 0.35, {
            "detail_scale": 260.0, "wear": 0.2,
        }),
    }


static func _make(color: Color, metallic: float, roughness: float, extra: Dictionary) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = SHADER
    mat.set_shader_parameter("base_color", color)
    mat.set_shader_parameter("metallic", metallic)
    mat.set_shader_parameter("roughness", roughness)
    for key in extra:
        mat.set_shader_parameter(key, extra[key])
    return mat
