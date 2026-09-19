shader_type canvas_item;
render_mode unshaded;

// Post-proceso bodycam: identidad de cámara (lente ancha + sensor barato) sin
// comerse el detalle.
//
// Medido sobre capturas reales del juego (misma imagen con y sin shader):
// - el blur direccional anterior quitaba un 38% de contraste a los bordes
//   fuertes al girar, y su normalización estaba mal (los pesos suman 3.197 y
//   dividía por 2.15, así que además aclaraba un 49% la imagen al girar);
// - el grano de 0.028 metía 5.5x más ruido que el propio render;
// - pow(0.9) + contraste 1.18 recortaba las altas luces.
// Aquí no hay blur: quedan distorsión de lente, aberración cromática, viñeta
// suave, grano de sensor sólo en sombras y una curva S que no recorta.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float distortion = 0.030;    // barril suave de lente ancha
uniform float chroma = 0.00020;      // aberración cromática hacia los bordes
                                     // (0.00045 emplastaba los bordes a 1px+ y
                                     // se leía como pixelado; identidad intacta)
uniform float vignette = 0.08;       // viñeta óptica sutil de cámara policial
uniform float grain_amount = 0.006;  // ruido de sensor (sólo sombras; 0.012
                                     // parpadeaba por pixel y se leia como
                                     // pixelado: la textura barata sigue)
uniform float exposure_pulse = 0.0;  // reacción del AGC al disparo
uniform float aim_amount = 0.0;
uniform float time = 0.0;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 cuv = SCREEN_UV - 0.5;

    // Compensación de escala: evita que la distorsión de barril expanda la
    // muestra fuera de [0, 1] y produzca clamping / estiramiento en los bordes.
    float max_corner_r2 = 0.5;
    float max_expand = 1.0 + distortion * max_corner_r2 + distortion * 0.42 * (max_corner_r2 * max_corner_r2) + chroma * 2.5;
    float lens_scale = 1.0 / max_expand;

    vec2 suv = cuv * lens_scale;
    float r2 = dot(suv, suv);
    float r4 = r2 * r2;

    // Lente: distorsión de barril compensada.
    vec2 duv = 0.5 + suv * (1.0 + distortion * r2 + distortion * 0.42 * r4);

    // Aberración cromática: crece con el radio, casi nula en el centro.
    vec2 dir = suv / max(sqrt(r2), 1e-4);
    float off = chroma * (0.25 + r2 * 1.5);
    vec3 col;
    col.r = texture(screen_texture, clamp(duv + dir * off, vec2(0.0005), vec2(0.9995))).r;
    col.g = texture(screen_texture, clamp(duv, vec2(0.0005), vec2(0.9995))).g;
    col.b = texture(screen_texture, clamp(duv - dir * off, vec2(0.0005), vec2(0.9995))).b;

    // El sensor reacciona al fogonazo, pero no se lava la imagen.
    col *= 1.0 + exposure_pulse * 0.10;

    // Curva S suave sobre luminancia: contraste limpio sin aplastar sombras ni recortar altas.
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col += vec3(luma * luma * (3.0 - 2.0 * luma) - luma) * 0.04;

    // Viñeta óptica sutil: cámara de seguridad/cuerpo policial nítida, sin túnel negro.
    float vig = smoothstep(1.40, 0.35, r2 * 1.15);
    col *= mix(1.0, vig, clamp(vignette + aim_amount * 0.03, 0.0, 1.0));

    // Ruido de sensor: monocromo, más visible en sombra (es donde el AGC sube
    // la ganancia). Es el único efecto que aporta "textura de cámara barata".
    float noise = hash21(SCREEN_UV * vec2(1920.0, 1080.0) + vec2(time * 97.3, time * 51.7)) - 0.5;
    float shadow = 1.0 - smoothstep(0.04, 0.45, luma);
    col += noise * grain_amount * (0.30 + 0.70 * shadow);

    COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
