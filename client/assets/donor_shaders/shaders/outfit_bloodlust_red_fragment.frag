// Bloodlust RED (EXTENDED) - the ORIGINAL bloodlust, but the base creature is
// first repainted to a near-desaturated dusty rose (STEP 1). STEP 2 is the
// bloodlust pass verbatim from outfit_blood_ext_fragment.frag - DO NOT retune it;
// the only thing this variation changes is the base color via paintRed().
//   STEP 1: luminance-driven dusty-rose repaint (keeps the sprite's shading).
//   STEP 2: unchanged bloodlust - rage veins, blood running, droplets, fury aura.
//   Uses outfit_divine_aura_ext_vertex.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3  BLOOD_DARK   = vec3(0.16, 0.00, 0.00);
const vec3  BLOOD        = vec3(0.60, 0.02, 0.02);
const vec3  BLOOD_BRIGHT = vec3(1.00, 0.10, 0.05);
const vec3  RAGE         = vec3(1.00, 0.28, 0.10);

// --- RED HUE PAINT (step 1) - near-desaturated dusty ROSE -------------------
const float RED_PAINT    = 1.0;   // 0 = original colors, 1 = fully repainted rose
const float RED_LO       = 0.06;  // luminance mapped to the darkest tone
const float RED_HI       = 0.92;  // luminance mapped to the brightest tone
const float RED_MID_MIX  = 0.30;  // pull midtones toward the mid rose
const float RED_SAT      = 0.45;  // <1 desaturates toward gray (near-0 = almost gray/pink)

// Dusty rose / mauve ramp: barely-there tint, R only slightly above G/B.
const vec3  RED_D_DARK   = vec3(0.17, 0.12, 0.13); // shadows: dark mauve-gray
const vec3  RED_D_MID    = vec3(0.46, 0.34, 0.35); // body: dusty rose-gray
const vec3  RED_D_HI     = vec3(0.80, 0.65, 0.66); // highlights: pale pink-gray
// ---------------------------------------------------------------------------

const float REACH_PX     = 18.0;
const float RIM_PX       = 3.0;
const float MARGIN_FADE  = 0.26;

const float WIDE_PX      = 22.0;
const float CIRC_LO      = 0.10;
const float CIRC_HI      = 0.40;

const float BEAT_SPEED   = 2.3;   // fast, angry heartbeat
const float BODY_DARK    = 0.55;  // original bloodlust value (do not change)
const float VEIN_STR     = 1.6;   // original bloodlust value (do not change)

const float DRIP_COLS    = 10.0;  // blood run columns
const float DRIP_SPEED   = 0.35;  // how fast blood oozes down (+ = down; flip if up)

// Blood droplet spray.
const float DROP_SCALE   = 10.0;
const vec2  DROP_GRAV    = vec2(0.06, 0.42); // sideways + downward fall (flip y if up)
const float DROP_MIN     = 0.10;
const float DROP_MAX     = 0.22;
const float BLOOD_GLOW   = 1.2;

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

// STEP 1 - repaint an original outfit color to a muted, dead red, keeping shading.
vec3 paintRed(vec3 c)
{
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    vec3 red = mix(RED_D_DARK, RED_D_HI, smoothstep(RED_LO, RED_HI, lum));
    red = mix(red, RED_D_MID, RED_MID_MIX);
    // Desaturate toward its own luminance for a deader, less vivid red.
    float rl = dot(red, vec3(0.299, 0.587, 0.114));
    red = mix(vec3(rl), red, RED_SAT);
    return mix(c, red, RED_PAINT);
}

// Blood running down: vertical dark streaks with a brighter oozing bead.
float drips(vec2 uv, float t)
{
    float x = uv.x * DRIP_COLS;
    float col = floor(x);
    vec2 r = hash2(vec2(col, 4.0));
    if (r.x < 0.45) return 0.0;
    float fx = fract(x) - 0.5;
    float streak = smoothstep(0.16, 0.02, abs(fx));               // thin vertical trail
    float bead = fract(uv.y * (1.5 + r.y) + t * DRIP_SPEED + r.x); // oozing bead scrolls down
    float head = smoothstep(0.35, 0.0, abs(bead - 0.5));
    return streak * (0.35 + 0.65 * head);
}

// Teardrop blood droplets spraying/falling. Fills coverage.
float droplets(vec2 uv, float t)
{
    float cover = 0.0;
    vec2 gp = uv * DROP_SCALE + DROP_GRAV * t;
    vec2 base = floor(gp);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 cell = base + vec2(float(x), float(y));
            vec2 r = hash2(cell + 9.0);
            if (r.x < 0.50) continue;
            vec2 c = cell + 0.5 + 0.24 * vec2(sin(t * (0.9 + r.y) + r.x * 6.2831),
                                              cos(t * (0.7 + r.x) + r.y * 6.2831));
            float size = mix(DROP_MIN, DROP_MAX, r.y);
            vec2 rel = gp - c;
            float stretch = rel.y < 0.0 ? 1.7 : 1.0;              // teardrop tail (trailing up)
            float d = length(vec2(rel.x, rel.y * stretch));
            cover = max(cover, smoothstep(size, size * 0.55, d));
        }
    }
    return cover;
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

    // Fast angry heartbeat.
    float bc = mod(t * BEAT_SPEED, 6.2831);
    float beat = pow(max(0.0, sin(bc * 2.0)), 6.0) + 0.6 * pow(max(0.0, sin(bc * 2.0 - 0.7)), 5.0);
    float throb = 0.88 + 0.12 * beat; // gentle breath, not a blink

    float circ = 0.2 + 0.8 * smoothstep(CIRC_LO, CIRC_HI, central);
    float drop = droplets(v_TexCoord, t) * circ;

    if (aHere > 0.5) {
        // STEP 1: paint the BASE creature (desaturated dusty rose). ONLY change.
        vec3 painted = paintRed(here.rgb);

        // STEP 2: ORIGINAL Bloodlust on top - unchanged, just fed the repainted base.
        vec3 body = mix(painted, BLOOD_DARK, BODY_DARK);

        vec2 vuv = v_TexCoord * 6.0;
        vuv += 0.3 * vec2(fbm(vuv * 0.6 + t * 0.15), fbm(vuv * 0.6 + 4.0));
        float rv = fbm(vuv);
        rv = 1.0 - abs(2.0 * rv - 1.0);
        float veins = pow(rv, 3.5);
        body += BLOOD_BRIGHT * veins * throb * VEIN_STR;

        // Blood running down (darkens + reddens).
        float run = drips(v_TexCoord, t);
        body = mix(body, BLOOD * 0.5, run * 0.7);

        // Faint "seeing red" surge on the beat (subtle, no blink).
        body += RAGE * beat * 0.06;

        float rim = clamp(1.0 - rimNbr, 0.0, 1.0);
        body += BLOOD_BRIGHT * rim * 0.4 * throb;

        // Droplets on the body too.
        body = mix(body, BLOOD_BRIGHT, drop * 0.7);

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Fury aura throbbing + blood droplets spraying out.
        if (reach < 0.03) discard;
        float life = smoothstep(0.0, MARGIN_FADE, reach);
        float dropA = drop * life;
        float glow = reach * 0.12 * throb;                 // throbbing red haze
        float auraI = max(glow, dropA * 0.95) * BLOOD_GLOW;
        if (auraI < 0.02) discard;

        vec3 col = mix(BLOOD_DARK, BLOOD, reach);
        col = mix(col, BLOOD_BRIGHT, drop);
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
