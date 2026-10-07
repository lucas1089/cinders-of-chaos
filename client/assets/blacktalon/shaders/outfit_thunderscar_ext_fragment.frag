// Thunderscar (EXTENDED) - BLACK lightning that leaves a CRIMSON burn behind it.
//
// The two elements are not layered on top of each other, they are cause and
// effect: a bolt snaps across the body, and the path it took keeps burning after
// it is gone. Fire only ever exists where lightning has already been.
//
//   - STRIKE SLOTS: time is quantised into strikes. Slot k seeds one bolt - its
//     angle, its offset and its jag are all deterministic functions of k, so the
//     shader can look BACKWARDS at slots k-1 and k-2 and draw where the previous
//     bolts landed. That is how a decaying trail is possible with no feedback
//     buffer and no state: the past is recomputed, not remembered.
//   - THE STRIKE IS DARK: the core of the bolt does not add light, it SUBTRACTS
//     it - a hairline of near-black cut through the creature, wrapped in a thin
//     crimson fringe that does glow. Black lightning reads instantly as wrong,
//     which is the point.
//   - THE SCAR: the same path, wider and softer, cooling through crimson-hot ->
//     blood -> ash over the next second and a half. Three scars are alive at
//     once, at different ages, so the body always carries the history of the last
//     few hits.
//   - CHARGE: crimson static crackles over the body just before the next strike
//     and snaps out at the moment it lands - the effect breathes on a beat.
//   - EMBERS lift off the scars, not off the silhouette, so the sparks trace the
//     path the lightning took.
//   - The palette is deliberately CRIMSON, never orange: the orange band belongs
//     to Cinderheart, and these two must not read as the same effect.
//   Uses outfit_divine_aura_ext_vertex.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Palette is overridable so a tinted variant can reuse this file by prepending
// its own #defines (see scripts/gen_shader_variants.js).
#ifndef CHAR_COLOR
#define CHAR_COLOR    vec3(0.07, 0.02, 0.02)
#endif
#ifndef BLOOD_DEEP
#define BLOOD_DEEP    vec3(0.42, 0.01, 0.03)
#endif
#ifndef BLOOD_COLOR
#define BLOOD_COLOR   vec3(0.90, 0.05, 0.09)
#endif
#ifndef CRIMSON_HOT
#define CRIMSON_HOT   vec3(1.00, 0.30, 0.18)
#endif
#ifndef ASH_COLOR
#define ASH_COLOR     vec3(0.16, 0.11, 0.11)
#endif
// The bolt core. Near-black on purpose: it is drawn by darkening, not by adding.
#ifndef BOLT_DARK
#define BOLT_DARK     vec3(0.015, 0.000, 0.010)
#endif

const float GLOW_PX      = 8.0;   // alpha blur reach
const float BODY_CHAR    = 0.66;  // how charred the untouched body is

const float STRIKE_RATE  = 1.55;  // seconds between strikes
const float SCAR_LIFE    = 1.45;  // seconds for a scar to cool to nothing
const float FLASH_DECAY  = 20.0;  // how fast the bolt itself disappears
const float BOLT_W       = 0.013; // dark core half-width, in quad units
const float FRINGE_W     = 3.6;   // crimson fringe, as a multiple of the core
const float SCAR_W       = 0.034; // scar half-width (wider than the bolt)
const float JAG          = 0.26;  // how much the path zig-zags
const float BRANCH_ODDS  = 0.50;  // fraction of strikes that fork

const float CHARGE_SCALE = 26.0;  // static crackle density
const float CHARGE_GLOW  = 0.60;

const float EMBER_SCALE  = 12.0;
const float EMBER_RISE   = 0.50;
const float EMBER_PX     = 1.25;  // ember radius, in PIXELS
const float MARGIN_OPAC  = 0.75;

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

// Cooling ramp for a scar. Crimson only - it must never pass through orange.
vec3 cool(float x)
{
    x = clamp(x, 0.0, 1.0);
    vec3 c = mix(ASH_COLOR,  BLOOD_DEEP,  smoothstep(0.00, 0.35, x));
    c      = mix(c,          BLOOD_COLOR, smoothstep(0.35, 0.72, x));
    c      = mix(c,          CRIMSON_HOT, smoothstep(0.80, 1.00, x));
    return c;
}

// DISTANCE to the path of strike k (quad space, centred). Angle, offset and jag
// all come from k, so any past strike can be reconstructed exactly. Returning the
// distance instead of an intensity lets one evaluation feed several widths - the
// dark core and its fringe come from the same fbm.
float boltDist(vec2 p, float k)
{
    vec2 r = hash2(vec2(k, 3.17));
    float ang = r.x * 6.2831;
    float ca = cos(ang), sa = sin(ang);
    vec2 q = vec2(ca * p.x + sa * p.y, -sa * p.x + ca * p.y);
    q.y -= (r.y - 0.5) * 0.34;                       // strikes are off-centre
    float jag = (fbm(vec2(q.x * 10.0, k * 7.3)) - 0.5) * JAG
              + 0.018 * sin(q.x * 85.0 + k * 4.0);   // fine kinks
    return abs(q.y - jag);
}

// Rising sparks, sized in PIXELS so they stay crisp dots at any zoom.
float embers(vec2 uv, float t, float pxLen)
{
    vec2 gp = uv * EMBER_SCALE + vec2(0.0, t * EMBER_RISE);
    vec2 base = floor(gp);
    float acc = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = base + vec2(float(i), float(j));
            vec2 h = hash2(c + 2.9);
            if (h.x < 0.50) continue;
            float drift = 0.30 * sin(t * (1.3 + 2.2 * h.y) + h.x * 6.2831);
            vec2 pos = c + vec2(0.5 + drift, 0.5);
            vec2 rel = (gp - pos) / EMBER_SCALE;
            float size = EMBER_PX * pxLen * (0.6 + 0.8 * h.y);
            float flick = 0.40 + 0.60 * sin(t * (5.0 + 9.0 * h.x) + h.y * 6.2831);
            acc = max(acc, smoothstep(size, size * 0.2, length(rel)) * max(flick, 0.0));
        }
    }
    return acc;
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;
    float pxLen = (px.x + px.y) * 0.5;

    float t = u_Time;
    vec2 uv = v_TexCoord;
    vec2 p = uv - 0.5;
    vec4 here = texture2D(u_Tex0, uv);
    float aHere = here.a;

    float aSum = aHere, cnt = 1.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, uv + dir * px * (GLOW_PX * 0.5)).a;
        aSum += texture2D(u_Tex0, uv + dir * px *  GLOW_PX).a;
        cnt += 2.0;
    }
    float blurA = aSum / cnt;

    // Strike clock.
    float sT    = t / STRIKE_RATE;
    float slot  = floor(sT);
    float phase = fract(sT);
    float flash = exp(-phase * FLASH_DECAY);          // the bolt, gone in a blink
    float charge = smoothstep(0.70, 1.00, phase);     // static building up again

    // The last three strikes, each at its own age, still burning.
    float scarHeat = 0.0;   // 0..1, how hot the hottest scar under this pixel is
    float scarMask = 0.0;   // coverage, for alpha in the margin
    for (int i = 0; i < 3; i++) {
        float age = (phase + float(i)) * STRIKE_RATE;
        float heat = exp(-age / SCAR_LIFE);
        if (heat < 0.02) continue;
        float band = smoothstep(SCAR_W, 0.0, boltDist(p, slot - float(i)));
        // Burning is uneven along the path: it eats in where the noise says so.
        float bite = 0.55 + 0.45 * fbm(vec2(p.x * 14.0 + slot, p.y * 14.0 - t * 0.6));
        scarHeat = max(scarHeat, band * heat * bite);
        scarMask = max(scarMask, band * heat);
    }

    // The live strike: one distance field, two zones. Dark core, crimson fringe.
    float dMain = boltDist(p, slot);
    float core   = smoothstep(BOLT_W, 0.0, dMain);
    float fringe = smoothstep(BOLT_W * FRINGE_W, BOLT_W * 0.85, dMain);
    if (hash2(vec2(slot, 9.4)).x < BRANCH_ODDS) {     // fork on half the strikes
        float dFork = boltDist(p, slot + 0.41);
        core   = max(core,   smoothstep(BOLT_W * 0.70, 0.0, dFork) * 0.9);
        fringe = max(fringe, smoothstep(BOLT_W * FRINGE_W * 0.8, BOLT_W * 0.6, dFork) * 0.85);
    }
    core   *= flash;
    fringe *= flash;

    if (aHere > 0.5) {
        vec3 body = mix(here.rgb, CHAR_COLOR, BODY_CHAR);

        // Crimson static crackling while the charge builds.
        float st = fbm(vec2(uv.x * CHARGE_SCALE, uv.y * CHARGE_SCALE) + floor(t * 22.0));
        st = pow(1.0 - abs(2.0 * st - 1.0), 9.0);
        body += BLOOD_COLOR * st * charge * CHARGE_GLOW;

        // The burning path left by the last strikes.
        body = mix(body, cool(scarHeat), smoothstep(0.02, 0.55, scarHeat) * 0.85);
        body += BLOOD_DEEP * scarHeat * 0.45;

        // The strike: fringe glows, then the core is punched through it in black.
        body += CRIMSON_HOT * fringe * 1.25;
        body += BLOOD_COLOR * flash * 0.08;           // the body flinches on impact
        body = mix(body, BOLT_DARK, core);

        float innerRim = clamp(1.0 - blurA, 0.0, 1.0);
        body += BLOOD_COLOR * innerRim * 0.45;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // The bolt does not stop at the silhouette - it carries on through the
        // margin for the instant it exists.
        float reachGate = smoothstep(0.01, 0.22, blurA);
        float arcCore   = core * reachGate;
        float arcFringe = fringe * reachGate;

        // Sparks lift off the scars, so they trace the path of the lightning.
        float spark = embers(uv, t, pxLen) * reachGate * (0.20 + 1.10 * scarMask);

        float auraI = max(max(arcCore, arcFringe * 0.95), spark * 0.90) * MARGIN_OPAC;
        if (auraI < 0.02) discard;

        // Crimson everywhere, black only in the hairline of the bolt itself.
        vec3 col = mix(BLOOD_COLOR, CRIMSON_HOT, min(spark, 1.0) * 0.6);
        col = mix(col, CRIMSON_HOT, min(arcFringe * 1.2, 1.0));
        col = mix(col, BOLT_DARK, min(arcCore * 1.3, 1.0));
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
