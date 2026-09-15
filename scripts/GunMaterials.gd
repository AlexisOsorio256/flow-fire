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
        # Armazón de polímero: dieléctrico (nada de metallic), rugoso y picado.
        # Antes llevaba metallic 0.04-0.70 y el arma se leía negra: en un
        # interior sin reflejos, el metal sólo refleja el cielo y el resto es
        # negro. Un polímero real es difuso: así la luz del viewmodel lo modela.
        "Frame": _make(Color(0.052, 0.053, 0.057), 0.0, 0.62, {
            "detail_scale": 210.0, "stipple": 0.75, "detail_albedo": 0.055, "wear": 0.14, "micro": 0.30,
        }),
        # Piezas negras (gatillo, seguros, piezas internas).
        "Black": _make(Color(0.032, 0.032, 0.036), 0.18, 0.48, {
            "detail_scale": 200.0, "detail_albedo": 0.05, "wear": 0.18,
        }),
        # Corredera: acero nitrurado, oscuro y semi-mate. Tenifer no es cromo:
        # poca componente especular y bastante rugosidad, o el reflejo del cielo
        # la deja en mancha blanca (medido: 15% de la corredera recortada).
        "Slide": _make(Color(0.058, 0.060, 0.066), 0.28, 0.40, {
            "detail_scale": 190.0, "streak": 0.5, "detail_roughness": 0.10, "wear": 0.22, "micro": 0.22,
        }),
        # Puntos y contorno de la mira: blancos, con un punto de emisión.
        # Puntos y contorno de la mira: pintura blanca, que devuelve luz aunque
        # esté a contraluz (si no, el punto de mira se ve negro y no sirve para
        # apuntar). Es lo que hace legible la mira en un interior oscuro.
        "White": _make(Color(0.84, 0.85, 0.87), 0.0, 0.42, {
            "detail_scale": 300.0, "wear": 0.0, "emission_color": Color(0.55, 0.56, 0.58),
            "emission_energy": 0.42,
        }),
        # Piezas grises (cañón, guía de muelle, extractor): acero desnudo.
        "GrayShade2": _make(Color(0.135, 0.14, 0.152), 0.80, 0.31, {
            "detail_scale": 130.0, "streak": 0.4, "wear": 0.25,
        }),
        # Cargador: cuerpo de acero con recubrimiento, más liso y brillante que
        # el polímero del armazón. Ese contraste es lo que permite verlo salir y
        # entrar en la recarga (antes era el mismo negro que el arma y
        # desaparecía contra ella y contra el guante).
        "Magazine": _make(Color(0.078, 0.079, 0.084), 0.42, 0.36, {
            "detail_scale": 190.0, "stipple": 0.25, "detail_albedo": 0.05, "wear": 0.22,
        }),
        # Cartuchos (los usa el cargador y la bala que se oculta).
        "BulletCasing": _make(Color(0.66, 0.47, 0.17), 0.90, 0.26, {
            "detail_scale": 260.0, "wear": 0.2,
        }),
        "BulletCasing2": _make(Color(0.55, 0.36, 0.13), 0.90, 0.30, {
            "detail_scale": 260.0, "wear": 0.2,
        }),
        "BulletTip": _make(Color(0.42, 0.18, 0.08), 0.55, 0.40, {
            "detail_scale": 260.0, "wear": 0.2,
        }),
        # Brazos del mismo rig: piel real (albedo ~0.3, no salmón plano), manga
        # de tejido y guante de polímero.
        "Shirt": _make(Color(0.115, 0.122, 0.135), 0.0, 0.90, {
            "detail_scale": 130.0, "detail_albedo": 0.08, "wear": 0.18,
            "micro": 0.55,
        }),
        "Skin": _make(Color(0.245, 0.170, 0.132), 0.0, 0.66, {
            "detail_scale": 150.0, "detail_albedo": 0.09, "wear": 0.10, "micro": 0.40,
        }),
        "Glove": _make(Color(0.042, 0.044, 0.048), 0.05, 0.62, {
            "detail_scale": 150.0, "detail_albedo": 0.09, "wear": 0.16, "micro": 0.30,
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
