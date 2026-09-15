shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Material del arma con detalle procedural.
//
// El GLB del Glock no trae ninguna textura (ni albedo, ni rugosidad, ni
// normal), así que con colores planos el arma se ve como un bloque. Aquí el
// grano del polímero, el picado de la empuñadura, el rayado de la corredera y
// el desgaste de bordes se generan con ruido sobre las UV del modelo: no hace
// falta ningún asset externo ni crédito de terceros.

uniform vec3 base_color : source_color = vec3(0.12, 0.12, 0.13);
uniform float metallic : hint_range(0.0, 1.0) = 0.45;
uniform float roughness : hint_range(0.0, 1.0) = 0.42;
uniform float detail_scale = 120.0;      // frecuencia del grano fino
uniform float detail_albedo = 0.10;      // cuánto varía el color con el grano
uniform float detail_roughness = 0.22;   // cuánto varía la rugosidad
uniform float stipple : hint_range(0.0, 1.0) = 0.0;   // picado (empuñadura)
uniform float streak : hint_range(0.0, 1.0) = 0.0;    // rayado de mecanizado
uniform float wear : hint_range(0.0, 1.0) = 0.35;     // desgaste en bordes
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
// Micro-rugosidad: rompe el reflejo a escala de milímetros. Es lo que evita que
// una superficie plana y sin textura se lea como plástico (el fallo que se veía
// en los brazos: caras grandes con un gris uniforme). No cuesta ninguna textura.
uniform float micro = 0.35;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    return 0.55 * vnoise(p) + 0.28 * vnoise(p * 2.3) + 0.17 * vnoise(p * 5.1);
}

void fragment() {
    float grain = fbm(UV * detail_scale);
    float brush = fbm(vec2(UV.x * 26.0, UV.y * 2.2));         // alargado: mecanizado
    float stipple_mask = smoothstep(0.52, 0.78, fbm(UV * detail_scale * 1.9));
    float wear_mask = smoothstep(0.66, 0.97, fbm(UV * 26.0)); // roce, no manchas

    float shade = 1.0 + (grain - 0.5) * detail_albedo * 2.0;
    shade *= 1.0 + (brush - 0.5) * 0.16 * streak;
    shade *= 1.0 - stipple_mask * 0.16 * stipple;
    // El roce quita material: aclara y pule sólo donde aprieta de verdad.
    shade *= 1.0 + wear_mask * 0.10 * wear;
    ALBEDO = base_color * shade;

    float r = roughness + (grain - 0.5) * detail_roughness;
    r = mix(r, r + (brush - 0.5) * 0.35, streak);
    r -= wear_mask * 0.25 * wear;                              // el roce pule
    // Micro-rugosidad independiente del albedo: el color queda limpio y es el
    // reflejo el que se rompe. Sólo ENGROSA (nunca pule): si deja zonas más
    // lisas que la base, el especular se dispara y recorta a blanco (medido:
    // 23-50% de los píxeles del arma recortados con la versión simétrica).
    // La frecuencia es de unos pocos milímetros: más fina que un píxel sólo
    // produce ruido de muestreo.
    float micro_noise = fbm(UV * detail_scale * 1.5 + vec2(11.3, 7.1));
    r += micro_noise * micro * 0.35;
    ROUGHNESS = clamp(r, 0.05, 1.0);

    // El metal desnudo asoma donde el roce es más fuerte.
    METALLIC = clamp(metallic + wear_mask * 0.35 * wear * metallic, 0.0, 1.0);

    EMISSION = emission_color * emission_energy;
}
