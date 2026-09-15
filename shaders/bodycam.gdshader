shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float distortion = 0.055;
uniform float chroma = 0.0014;
uniform float vignette = 0.62;
uniform float grain_amount = 0.055;
uniform float exposure_pulse = 0.0;
uniform float blur_amount = 0.0;
uniform vec2 blur_dir = vec2(0.0, 0.0);
uniform float time = 0.0;
uniform float aim_amount = 0.0;
uniform float speed_amount = 0.0;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

vec3 scene_color(vec2 uv) {
    return texture(screen_texture, uv).rgb;
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 cuv = uv - 0.5;
    float r2 = dot(cuv, cuv);
    float r4 = r2 * r2;

    vec2 duv = 0.5 + cuv * (1.0 + distortion * r2 + distortion * 0.42 * r4);
    vec2 center_dir = normalize(cuv + vec2(1e-5));
    float chroma_off = chroma * (0.22 + r2 * 1.25) + exposure_pulse * 0.002;

    vec3 col;
    col.r = texture(screen_texture, duv + center_dir * chroma_off).r;
    col.g = texture(screen_texture, duv).g;
    col.b = texture(screen_texture, duv - center_dir * chroma_off).b;

    if (blur_amount > 0.00015) {
        vec3 blur = col * 0.34;
        for (int i = 1; i <= 5; i++) {
            float w = 1.0 - float(i) / 7.0;
            blur += scene_color(duv + blur_dir * blur_amount * float(i) * 0.24) * w;
        }
        col = mix(col, blur / 2.15, clamp(blur_amount * 95.0, 0.0, 0.72));
    }

    col *= 1.0 + exposure_pulse * 0.42;

    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(luma), col, 0.92 - aim_amount * 0.04);
    col = pow(max(col, vec3(0.0)), vec3(0.9));
    col = (col - 0.5) * 1.18 + 0.5;
    col += vec3(-0.012, -0.004, 0.02) * (1.0 - smoothstep(0.0, 0.55, luma));

    float vig = smoothstep(1.05, 0.18, r2 * 1.38);
    col *= mix(1.0, vig, clamp(vignette + aim_amount * 0.06, 0.0, 1.0));

    float grain = hash21(uv * vec2(1920.0, 1080.0) + vec2(time * 91.7, time * 47.3)) - 0.5;
    col += grain * (grain_amount + speed_amount * 0.02);

    COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
