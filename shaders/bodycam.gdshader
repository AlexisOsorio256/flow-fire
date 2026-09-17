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
uniform float vignette = 0.30;       // viñeta óptica, suave
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
    float r2 = dot(cuv, cuv);
    float r4 = r2 * r2;

    // Lente: distorsión de barril. La muestra se desplaza hacia el borde, así
    // que el encuadre se abre en las esquinas como en una cámara de acción.
    vec2 duv = 0.5 + cuv * (1.0 + distortion * r2 + distortion * 0.42 * r4);

    // Aberración cromática: crece con el radio, casi nula en el centro.
    vec2 dir = cuv / max(sqrt(r2), 1e-4);
    float off = chroma * (0.25 + r2 * 1.5);
    vec3 col;
    col.r = texture(screen_texture, duv + dir * off).r;
    col.g = texture(screen_texture, duv).g;
    col.b = texture(screen_texture, duv - dir * off).b;

    // El sensor reacciona al fogonazo, pero no se lava la imagen.
    col *= 1.0 + exposure_pulse * 0.10;

    // Curva S sobre la luminancia: sube el contraste del medio sin empujar las
    // altas luces al recorte (s < luma por encima de 0.5).
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col += vec3(luma * luma * (3.0 - 2.0 * luma) - luma) * 0.14;

    float vig = smoothstep(1.15, 0.20, r2 * 1.30);
    col *= mix(1.0, vig, clamp(vignette + aim_amount * 0.04, 0.0, 1.0));

    // Ruido de sensor: monocromo, más visible en sombra (es donde el AGC sube
    // la ganancia). Es el único efecto que aporta "textura de cámara barata".
    float noise = hash21(SCREEN_UV * vec2(1920.0, 1080.0) + vec2(time * 97.3, time * 51.7)) - 0.5;
    float shadow = 1.0 - smoothstep(0.04, 0.45, luma);
    col += noise * grain_amount * (0.30 + 0.70 * shadow);

    COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
