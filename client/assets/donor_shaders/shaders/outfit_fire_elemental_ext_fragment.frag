// Fire Elemental (EXTENDED) fragment - the character is not "tinted", it BECOMES
// living flame. Built from scratch on a different idea than the other effects:
//
//   - The silhouette is treated as FUEL. Real fire only rises, so everything is
//     sampled DIRECTIONALLY UPWARD, not as a symmetric aura:
//       * Body fill: a vertical heat gradient (hot white/yellow at the feet,
//         cooling to red at the top) found by measuring how much silhouette sits
//         ABOVE each pixel, all churned by upward-advected turbulence.
//       * Flames above: for pixels in the margin, we look DOWN toward the body;
//         if fuel is close enough and the rising turbulence reaches, a tapering
//         flame tongue licks up out of the head/shoulders.
//   No Voronoi, no particle grid, no edge-blur aura, no scanline - all new.
//
// Runs on the composited framebuffer (already colored -> no u_Color mask).
// dFdx/dFdy give the texel size. Uses outfit_divine_aura_ext_vertex.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// "Up" in framebuffer space. If the flames come out the FEET instead of the
// head, flip this to vec2(0.0, 1.0).
const vec2  FLAME_UP    = vec2(0.0, -1.0);

const float FLOW_SPEED  = 2.4;   // how fast fire churns upward
const float NOISE_SX    = 7.0;   // horizontal flame detail
const float NOISE_SY    = 3.5;   // vertical flame stretch (smaller = taller licks)

const float GRAD_PX     = 46.0;  // reach of the "hot at the feet" gradient
const float FLAME_PX    = 26.0;  // how high flames rise above the silhouette
const float BODY_HEAT   = 1.15;  // body fire brightness
const float AURA_HEAT   = 1.5;   // rising-flame brightness

vec2 hash2(vec2 p)
{
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(i).x;
    float b = hash2(i + vec2(1.0, 0.0)).x;
    float c = hash2(i + vec2(0.0, 1.0)).x;
    float d = hash2(i + vec2(1.0, 1.0)).x;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p)
{
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.0; a *= 0.5; }
    return s;
}

// Blackbody-ish fire ramp: 0 = dark ember, 1 = white hot.
vec3 heat(float x)
{
    x = clamp(x, 0.0, 1.0);
    vec3 c = mix(vec3(0.10, 0.0, 0.0), vec3(0.75, 0.06, 0.0), smoothstep(0.00, 0.30, x));
    c      = mix(c,                    vec3(1.0, 0.42, 0.03), smoothstep(0.30, 0.58, x));
    c      = mix(c,                    vec3(1.0, 0.85, 0.22), smoothstep(0.58, 0.82, x));
    c      = mix(c,                    vec3(1.0, 1.0, 0.90),  smoothstep(0.82, 1.00, x));
    return c;
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;
    vec4 here = texture2D(u_Tex0, v_TexCoord);
    float aHere = here.a;

    // Upward-advected turbulence: the living motion of the flame.
    vec2 fuv = vec2(v_TexCoord.x * NOISE_SX, v_TexCoord.y * NOISE_SY) + FLAME_UP * (t * FLOW_SPEED);
    float n = 0.65 * fbm(fuv) + 0.35 * fbm(fuv * 2.1 + FLAME_UP * (t * FLOW_SPEED * 0.6));

    if (aHere > 0.5) {
        // How much silhouette sits ABOVE this pixel -> near the feet = lots above
        // = hottest. Gives a self-contained vertical heat gradient.
        float aboveMass = 0.0;
        for (int k = 1; k <= 8; k++) {
            float d = (float(k) / 8.0) * GRAD_PX;
            aboveMass += texture2D(u_Tex0, v_TexCoord + FLAME_UP * (d * px.y)).a;
        }
        aboveMass /= 8.0;

        float heatBase = mix(0.42, 1.0, aboveMass);      // feet hot, head cooler
        float h = heatBase * (0.55 + 0.7 * n);           // churned by turbulence

        // Let brighter parts of the original outfit read as hotter embers.
        float lum = dot(here.rgb, vec3(0.299, 0.587, 0.114));
        h += lum * 0.15;

        gl_FragColor = vec4(clamp(heat(h) * BODY_HEAT, 0.0, 1.0), here.a);
    } else {
        // Look DOWN toward the body: the closer the fuel and the stronger the
        // rising turbulence, the higher a flame tongue reaches here.
        float fuel = 0.0;
        for (int k = 1; k <= 12; k++) {
            float frac = float(k) / 12.0;
            vec2 s = v_TexCoord - FLAME_UP * (frac * FLAME_PX * px.y); // toward body
            float a = texture2D(u_Tex0, s).a;
            fuel = max(fuel, a * (1.0 - frac));          // nearer body -> stronger, tapering up
        }
        if (fuel < 0.01) discard;

        // Shape the tongue with the rising turbulence; sharpen so it breaks up.
        float flame = smoothstep(0.32, 0.9, fuel * (0.4 + 1.1 * n));
        if (flame < 0.02) discard;

        float hot = clamp(fuel * 1.5, 0.0, 1.0);         // near the body = white hot
        vec3 col = heat(0.30 + 0.6 * hot);
        gl_FragColor = vec4(clamp(col * AURA_HEAT, 0.0, 1.0), clamp(flame, 0.0, 1.0));
    }
}
