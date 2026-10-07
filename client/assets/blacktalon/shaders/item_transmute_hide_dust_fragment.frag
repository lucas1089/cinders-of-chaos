// Transmute Transition - HIDE (dust disintegration / "Thanos snap").
// The OLD sprite crumbles into drifting ash as u_var0 goes 0 -> 1, with a warm
// ember edge at the dissolving front. Pairs with the dust REVEAL so the old
// sprite blows away while the new one reassembles.
//
// The original top-to-bottom wipe hide is kept as a backup in:
//   item_transmute_hide_fragment.frag
//
// Uniforms provided by the transmute draw path:
//   u_Tex0  - the sprite texture
//   u_Time  - global time (seconds)
//   u_var0  - progress: 0.0 = fully solid, 1.0 = fully dust/gone
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform float u_var0;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;

const float ALPHA_THRESHOLD = 0.004;
const float NOISE_SCALE     = 9.0;             // dust grain (higher = finer)
const float BURN_WIDTH      = 0.11;            // width of the ember front
const vec3  EMBER_COL       = vec3(1.00, 0.55, 0.16); // warm ember at the front
const vec3  ASH_COL         = vec3(0.46, 0.46, 0.49); // drifting ash particles

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i + vec2(0.0, 0.0));
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += valueNoise(p) * amp;
        p = p * 2.03 + vec2(7.13, 11.17);
        amp *= 0.5;
    }
    return v;
}

void main() {
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    if (texColor.a <= ALPHA_THRESHOLD) {
        discard;
    }

    // Crumble in the EARLIER part of the transition so the old sprite is gone
    // before the new one reassembles. (Small overlap with the reveal keeps the
    // dust continuous.)
    float progress = clamp(clamp(u_var0, 0.0, 1.0) / 0.60, 0.0, 1.0);
    vec2 uv = v_TexCoord;

    // Per-pixel dissolve field: decides the order in which pixels crumble.
    float n1 = fbm(uv * NOISE_SCALE + vec2(1.37, -2.11));
    float n2 = fbm(uv * NOISE_SCALE * 0.65 + vec2(-4.43, 3.19));
    float field = n1 * 0.72 + n2 * 0.28;            // ~0..1

    // As progress rises the threshold sweeps past the field -> pixels dissolve.
    float threshold = progress * 1.12;
    float d = field - threshold;                    // >0 = still solid
    float survive = smoothstep(-0.04, 0.08, d);     // solid mask, shrinks to 0

    // Glowing ember front where pixels are crumbling right now.
    float edge = 1.0 - smoothstep(0.0, BURN_WIDTH, abs(d));
    edge *= smoothstep(0.0, 0.12, progress);        // suppress a flash at t=0

    // Drifting ash detached from the dissolved region, lifting away on the wind.
    vec2 wind = normalize(vec2(0.25, -1.0));
    float lift = 0.20 * progress;
    vec2 turb = vec2(
        valueNoise(uv * 15.0 + vec2(u_Time * 1.7, -u_Time * 1.3)) - 0.5,
        valueNoise(uv * 13.0 + vec2(-u_Time * 1.1, u_Time * 1.6)) - 0.5) * 0.05;
    float ashSrc   = texture2D(u_Tex0, uv - wind * lift + turb).a;
    float ashNoise = valueNoise(uv * 22.0 + vec2(u_Time * 6.0, -u_Time * 6.5));
    float ashMask  = step(0.62, ashNoise);
    float ashGate  = smoothstep(0.05, 0.9, progress) * (1.0 - survive);
    float ashAlpha = ashSrc * ashMask * ashGate * 0.7;

    vec3 shaded = mix(texColor.rgb, EMBER_COL, edge * 0.9);

    // Guarantee full disappearance by the end.
    float fadeOut  = smoothstep(1.0, 0.85, progress);
    float finalAlpha = (texColor.a * survive + ashAlpha) * fadeOut;
    if (finalAlpha <= ALPHA_THRESHOLD) {
        discard;
    }

    vec3 finalColor = shaded * survive + ASH_COL * ashAlpha + EMBER_COL * edge * 0.40;
    gl_FragColor = vec4(clamp(finalColor, 0.0, 1.0), finalAlpha);
}
