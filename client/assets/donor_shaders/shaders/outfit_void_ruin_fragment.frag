// GENERATED FILE - do not edit. Palette variant of outfit_void_ext_fragment.frag.
// Tune the effect there, tune the colours in
// scripts/gen_shader_variants.js, then rerun:
//   node scripts/gen_shader_variants.js
#define VOID_BLACK vec3(0.05, 0.00, 0.01)
#define VOID_PURPLE vec3(0.42, 0.03, 0.03)
#define EDGE_PURPLE vec3(0.95, 0.12, 0.10)
// Void Tendrils (EXTENDED) - shadow / void with writhing tentacle filaments.
// Robust approach (no reliance on a framebuffer center): the tendrils are
// domain-warped ridged-fbm filaments (like the nature vines, but bolder) that
// writhe over time, reach OUT of the silhouette into the margin, and glow with an
// eldritch purple edge. Body is consumed by darkness with swirling shadow smoke.
// Uses outfit_divine_aura_ext_vertex.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Palette is overridable so tinted variants can reuse this single file: a variant
// prepends its own #defines to this source before compiling (see "Ruin Tendrils"
// in modules/game_shaders/shaders.lua). Tuning the tendrils stays a one-file edit.
// EDGE_* is added on top of the body, so keep it bright but roughly <= 1.0.
#ifndef VOID_BLACK
#define VOID_BLACK  vec3(0.02, 0.00, 0.03)
#endif
#ifndef VOID_PURPLE
#define VOID_PURPLE vec3(0.28, 0.05, 0.42)
#endif
// eldritch glow
#ifndef EDGE_PURPLE
#define EDGE_PURPLE vec3(0.65, 0.15, 0.95)
#endif

const float REACH_PX      = 20.0;
const float RIM_PX        = 3.0;
const float MARGIN_FADE   = 0.34;
const float TENDRIL_SCALE = 5.0;   // filament thickness/density (lower = thicker)
const float WRITHE        = 0.30;   // writhe speed
const float VOID_GLOW     = 1.15;

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

// Writhing tendril field: domain-warped ridged noise -> branching filaments.
float tendrils(vec2 uv, float t)
{
    vec2 tuv = uv * TENDRIL_SCALE;
    tuv += 0.6 * vec2(fbm(tuv * 0.5 + vec2(t * WRITHE, 1.0)),
                      fbm(tuv * 0.5 + vec2(3.0, t * WRITHE * 0.8)));
    float rv = fbm(tuv);
    return 1.0 - abs(2.0 * rv - 1.0); // 0..1, high along the tendril centerlines
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;
    vec4 here = texture2D(u_Tex0, v_TexCoord);
    float aHere = here.a;

    float aSum = aHere, cnt = 1.0, rimSum = 0.0, rimCnt = 0.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (REACH_PX * 0.5)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  REACH_PX).a;
        cnt += 2.0;
        rimSum += texture2D(u_Tex0, v_TexCoord + dir * px * RIM_PX).a;
        rimCnt += 1.0;
    }
    float reach  = aSum / cnt;
    float rimNbr = rimSum / rimCnt;

    float tv   = tendrils(v_TexCoord, t);
    float fil  = smoothstep(0.52, 0.80, tv);  // filament body
    float core = smoothstep(0.68, 0.96, tv);  // bright core
    float smoke = fbm(v_TexCoord * 7.0 + vec2(sin(t * 0.2), t * 0.15));

    if (aHere > 0.5) {
        // Body consumed by the void, with dark tendrils crawling over it.
        vec3 body = mix(here.rgb, VOID_BLACK, 0.80);
        body = mix(body, VOID_PURPLE, smoke * 0.20);
        float rim = clamp(1.0 - rimNbr, 0.0, 1.0);
        body += EDGE_PURPLE * rim * 0.35;

        body = mix(body, VOID_BLACK, fil * 0.55);   // dark tendril body
        body += EDGE_PURPLE * core * 0.7;           // glowing edges
        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        if (reach < 0.03) discard;
        float life = smoothstep(0.0, MARGIN_FADE, reach);
        float tendA = fil * life;
        float auraI = max(reach * 0.05, tendA) * VOID_GLOW; // filaments carry the alpha
        if (auraI < 0.02) discard;

        // Tendrils reaching out: deep violet body + bright eldritch core.
        vec3 col = mix(VOID_BLACK, VOID_PURPLE, reach * 0.5);
        col = mix(col, VOID_PURPLE, fil);
        col += EDGE_PURPLE * core;
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
