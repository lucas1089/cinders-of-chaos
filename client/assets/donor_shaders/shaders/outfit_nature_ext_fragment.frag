// Overgrowth / Nature 3.0 (EXTENDED) - an enchanted-forest takeover.
//   - Body: mossy stone + DAPPLED CANOPY LIGHT dancing over it + CREEPING VINES
//     (ridged-fbm filaments) crawling along the silhouette + lichen speckles.
//   - LEAVES tumble on gusts of wind (varied, lively) around the center of mass.
//   - Golden-green FIREFLIES / pollen drift and twinkle, on the body and floating
//     out into the aura.
//   - A soft earthy-green glow reaches into the margin.
//   Uses outfit_divine_aura_ext_vertex.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3  MOSS_DARK   = vec3(0.09, 0.16, 0.06);
const vec3  MOSS_LIGHT  = vec3(0.34, 0.62, 0.20);
const vec3  LEAF_GREEN  = vec3(0.30, 0.68, 0.16);
const vec3  LEAF_AUTUMN = vec3(0.86, 0.55, 0.10);
const vec3  LEAF_VEIN   = vec3(0.12, 0.30, 0.08);
const vec3  VINE        = vec3(0.15, 0.33, 0.09);
const vec3  DAPPLE      = vec3(0.55, 0.88, 0.32);
const vec3  FIREFLY     = vec3(0.88, 1.00, 0.45);

const float REACH_PX     = 16.0;
const float RIM_PX       = 3.0;
const float MOSS_STR     = 0.24;
const float MARGIN_FADE  = 0.24;

const float WIDE_PX      = 22.0;
const float CIRC_LO      = 0.10;
const float CIRC_HI      = 0.40;

const float LEAF_SCALE   = 9.0;
const vec2  LEAF_WIND    = vec2(0.06, 0.24); // base wind (x) + fall (y). Flip y if they rise.
const float LEAF_LEN     = 0.23;
const float LEAF_WID     = 0.115;

const float FIRE_SCALE   = 8.0;
const float NATURE_GLOW  = 1.15;

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

vec2 rot2(vec2 p, float a)
{
    float s = sin(a), c = cos(a);
    return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Dappled canopy light (soft moving bright patches).
float dappled(vec2 uv, float t)
{
    vec2 p = uv * 6.0;
    float c = sin(p.x * 1.3 + t * 0.5) + sin(p.y * 1.5 - t * 0.4) + sin((p.x + p.y) * 0.9 + t * 0.3);
    c *= 0.3333;
    return pow(0.5 + 0.5 * c, 3.0);
}

// Golden-green fireflies / pollen motes, drifting + twinkling.
float fireflies(vec2 uv, float t)
{
    float g = 0.0;
    vec2 gp = uv * FIRE_SCALE + vec2(0.10 * sin(t * 0.3), -0.10 * t);
    vec2 base = floor(gp);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 cell = base + vec2(float(x), float(y));
            vec2 r = hash2(cell + 17.0);
            if (r.x < 0.45) continue;                 // more of them
            vec2 c = cell + 0.5 + 0.34 * vec2(sin(t * (0.7 + r.y) + r.x * 6.2831),
                                              cos(t * (0.9 + r.x) + r.y * 6.2831));
            float tw = 0.45 + 0.55 * pow(0.5 + 0.5 * sin(t * 3.0 + r.x * 6.2831), 2.0);
            float d = length(gp - c);
            float core = smoothstep(0.07, 0.0, d);    // small bright point
            float halo = smoothstep(0.14, 0.0, d) * 0.20; // just a tiny glow, no smoke
            g = max(g, (core + halo) * tw);
        }
    }
    return g;
}

// Tumbling leaves on the wind. Fills leafCol + coverage.
void leaves(vec2 uv, float t, out vec3 leafCol, out float cover)
{
    cover = 0.0; leafCol = vec3(0.0);
    vec2 wind = LEAF_WIND + vec2(0.12 * sin(t * 0.25), 0.05 * sin(t * 0.5)); // gentle gusts
    vec2 gp = uv * LEAF_SCALE + wind * t;
    vec2 base = floor(gp);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 cell = base + vec2(float(x), float(y));
            vec2 r = hash2(cell);
            if (r.x < 0.45) continue;

            vec2 c = cell + 0.5 + 0.20 * vec2(sin(t * (0.5 + r.y) + r.x * 6.2831),
                                              cos(t * (0.7 + r.x) + r.y * 6.2831));
            float rot = t * (0.5 + 0.6 * r.y) + r.x * 6.2831;   // gentle tumble
            vec2 lr = rot2(gp - c, rot);

            float L = LEAF_LEN * (0.7 + 0.6 * r.y);
            float W = LEAF_WID * (0.7 + 0.6 * r.x);
            float vv = lr.y / L;
            float halfW = (1.0 - vv * vv) * W;
            float inLeaf = smoothstep(halfW, halfW * 0.55, abs(lr.x)) * step(abs(lr.y), L);
            if (inLeaf <= cover) continue;

            vec3 lc = mix(LEAF_GREEN, LEAF_AUTUMN, r.y * r.y);
            float vein = smoothstep(W * 0.14, 0.0, abs(lr.x));
            lc = mix(lc, LEAF_VEIN, vein * 0.8);
            lc = mix(lc * 0.7, lc, inLeaf);
            cover = inLeaf;
            leafCol = lc;
        }
    }
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;
    vec4 here = texture2D(u_Tex0, v_TexCoord);
    float aHere = here.a;

    float aSum = aHere, cnt = 1.0, rimSum = 0.0, rimCnt = 0.0, central = 0.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (REACH_PX * 0.5)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  REACH_PX).a;
        cnt += 2.0;
        rimSum += texture2D(u_Tex0, v_TexCoord + dir * px * RIM_PX).a;
        rimCnt += 1.0;
        central += texture2D(u_Tex0, v_TexCoord + dir * px * (WIDE_PX * 0.6)).a;
        central += texture2D(u_Tex0, v_TexCoord + dir * px *  WIDE_PX).a;
    }
    float reach  = aSum / cnt;
    float rimNbr = rimSum / rimCnt;
    central /= 16.0;

    vec3 leafCol; float cover;
    leaves(v_TexCoord, t, leafCol, cover);
    float circ = 0.15 + 0.85 * smoothstep(CIRC_LO, CIRC_HI, central);
    cover *= circ;

    float ff = fireflies(v_TexCoord, t);

    // Creeping vines: ridged-fbm filaments concentrated on the silhouette edge.
    float edgeBand = 1.0 - abs(2.0 * reach - 1.0);
    vec2 vuv = v_TexCoord * 8.0 + vec2(sin(v_TexCoord.y * 10.0 + t * 0.3) * 0.2, t * 0.05);
    float rv = fbm(vuv);
    rv = 1.0 - abs(2.0 * rv - 1.0);
    float vines = pow(rv, 4.0) * edgeBand * (0.6 + 0.4 * sin(v_TexCoord.y * 6.0 - t));

    if (aHere > 0.5) {
        // Mossy stone + canopy light + vines + lichen + leaves + fireflies.
        vec3 body = mix(here.rgb, MOSS_DARK, 0.30);
        float moss = fbm(v_TexCoord * 14.0 + t * 0.03);
        body += MOSS_LIGHT * smoothstep(0.55, 0.85, moss) * MOSS_STR;
        body += DAPPLE * dappled(v_TexCoord, t) * 0.13;
        body += LEAF_GREEN * step(0.93, hash2(floor(v_TexCoord * 60.0)).x) * 0.22;

        float rim = clamp(1.0 - rimNbr, 0.0, 1.0);
        body += MOSS_LIGHT * rim * 0.30;

        body = mix(body, VINE, clamp(vines, 0.0, 1.0) * 0.85);
        body = mix(body, leafCol, cover * 0.92);
        body += FIREFLY * ff * 1.6;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        if (reach < 0.03) discard;
        float life = smoothstep(0.0, MARGIN_FADE, reach);
        float leafA = cover * life;
        float ffA = ff * smoothstep(0.0, 0.35, reach);
        float vineA = clamp(vines, 0.0, 1.0) * life;
        float glow = reach * 0.015;                   // barely-there green hint
        float auraI = max(max(glow, leafA), max(ffA, vineA)) * NATURE_GLOW;
        if (auraI < 0.02) discard;

        vec3 col = mix(MOSS_DARK, MOSS_LIGHT, reach * 0.4);
        col = mix(col, VINE, vineA);
        col = mix(col, leafCol, cover);
        col += FIREFLY * ffA * 1.6;
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
