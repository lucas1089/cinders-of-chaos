// Event Horizon (EXTENDED) - the creature as a hole punched through space.
// Shares only the SKELETON of the Storm Lightning bolts (a polar field around the
// body center + the blurred-alpha reach into the margin); every mechanic on top
// of it is different:
//   - ACCRETION ARMS: the polar field is sheared by -log(radius), so instead of
//     straight bolts the arms wind into a LOGARITHMIC SPIRAL that tightens as it
//     falls toward the body, and the whole disc rotates forever.
//   - INFALLING STARS: a starfield laid out in (angle, log-radius) space and
//     scrolled along log-radius, so every star spirals INWARD and accelerates as
//     it closes in, smearing into a radial streak right before it is swallowed.
//   - EVENT HORIZON: a thin ring keyed on the SILHOUETTE (blurred alpha), not on
//     radius, so it hugs the sprite; the body darkens just inside it - light does
//     not come back out.
//   - COLLAPSE WAVE: one slow shockwave ring expanding out and dying on a long
//     cycle, replacing the electric discharge flashes.
//   - The body is a window into deep space: near-black with drifting nebula.
//   Uses outfit_divine_aura_ext_vertex.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Palette is overridable so a tinted variant can reuse this file by prepending
// its own #defines (same trick as outfit_void_ext_fragment / scripts/gen_shader_variants.js).
#ifndef VOID_DEEP
#define VOID_DEEP     vec3(0.02, 0.01, 0.06)
#endif
#ifndef COSMIC_BLUE
#define COSMIC_BLUE   vec3(0.08, 0.16, 0.62)
#endif
#ifndef COSMIC_VIOLET
#define COSMIC_VIOLET vec3(0.46, 0.12, 0.85)
#endif
#ifndef STAR_COLOR
#define STAR_COLOR    vec3(0.82, 0.86, 1.00)
#endif

const float REACH_PX     = 22.0;
const float RIM_PX       = 3.0;
const float MARGIN_FADE  = 0.30;

// Accretion spiral. ARM_COUNT must stay an INTEGER: the arm coordinate is
// fract(ang01 * ARM_COUNT + ...) and ang01 wraps 1 -> 0 behind the creature, so a
// fractional count would leave a visible seam there.
const float ARM_COUNT    = 5.0;
const float ARM_WIDTH    = 0.17;  // angular half-width of an arm, in arm space
const float SPIRAL_TWIST = 1.55;  // how hard -log(r) winds the arms inward
const float SWIRL_SPEED  = 0.16;  // disc rotation
const float ARM_TURB     = 0.45;  // fbm ragging, so the arms are gas and not geometry
const float ARM_GLOW     = 0.95;

// Infalling starfield. STAR_RINGS is an INTEGER for the same seam reason.
const float STAR_RINGS   = 26.0;  // stars around the circle
const float STAR_ROWS    = 3.2;   // star rows per unit of log-radius
const float INFALL       = 0.34;  // fall speed along log-radius
// Star size is in SCREEN PIXELS, not in grid cells: a polar cell is physically
// tiny near the body and huge out in the margin, so a size in cell units draws
// fat blobs on the outside. Converting the cell offset to texcoord units first
// keeps every star the same crisp size wherever it is.
const float STAR_PX      = 1.15;  // core radius, in pixels
const float STAR_HALO    = 3.4;   // bloom radius, as a multiple of the core
const float STAR_SMEAR   = 1.7;   // radial stretch of a star about to be swallowed
const float STAR_GLOW    = 1.0;

const float WAVE_PERIOD  = 4.5;   // seconds between collapse waves
const float VOID_GLOW    = 1.2;

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

// Spiral accretion arms. Everything added to the angle depends on radius or time
// only, never on the angle itself, so the field is continuous around the seam.
float arms(float rad, float ang01, float t)
{
    float r = max(rad, 0.04);
    float turns = ang01 * ARM_COUNT
                - SPIRAL_TWIST * log(r)          // logarithmic spiral: tightens inward
                + t * SWIRL_SPEED
                + ARM_TURB * (fbm(vec2(r * 7.0, t * 0.20)) - 0.5);
    float a = fract(turns);
    float core = smoothstep(ARM_WIDTH, 0.0, abs(a - 0.5));
    // Denser near the body, thinning out into the far margin.
    return core * smoothstep(0.75, 0.16, rad);
}

// Stars falling in. The grid lives in (angle, log-radius), so scrolling it along
// log-radius drags every star toward the center and makes it SPEED UP on the way:
// one grid row covers less and less screen distance as the radius shrinks.
float stars(float rad, float ang01, float t, float pxLen)
{
    float r = max(rad, 0.03);
    vec2 sp = vec2(ang01 * STAR_RINGS, log(r) * STAR_ROWS + t * INFALL);
    vec2 base = floor(sp);

    // Size of one grid cell in texcoord units at this radius: the arc it spans
    // around the circle, and the radial band d(r) that one log-radius row covers.
    // Offsets go through this before being measured, so the star is round and the
    // same size everywhere instead of scaling with the cell.
    vec2 cellSize = vec2(6.2831 * r / STAR_RINGS, r / STAR_ROWS);

    // Radial smear: a star about to be swallowed streaks along the fall direction.
    float stretch = 1.0 + STAR_SMEAR * smoothstep(0.50, 0.06, rad);

    float acc = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = base + vec2(float(i), float(j));
            // Wrap the ring index so the cells behind the creature line up.
            vec2 h = hash2(vec2(mod(c.x, STAR_RINGS), c.y) + 5.3);
            if (h.x < 0.42) continue;                 // sparse field
            vec2 pos = c + vec2(0.18 + 0.64 * h.x, 0.18 + 0.64 * h.y);
            vec2 rel = (sp - pos) * cellSize;         // -> texcoord units
            float d = length(vec2(rel.x, rel.y / stretch));

            float core  = STAR_PX * pxLen * (0.75 + 0.5 * h.y);
            float twink = 0.55 + 0.45 * sin(t * (2.0 + 5.0 * h.x) + h.y * 6.2831);
            // Pinpoint core + a soft bloom, so it reads as a star instead of a
            // flat white dot with a hard edge.
            float dot  = smoothstep(core, core * 0.25, d);
            float halo = smoothstep(core * STAR_HALO, core * 0.6, d) * 0.30;
            acc = max(acc, (dot + halo) * twink);
        }
    }
    return acc;
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

    vec2  p     = v_TexCoord - 0.5;
    float rad   = length(p);
    float ang01 = atan(p.y, p.x) * 0.159155 + 0.5;   // 0..1 around the center

    float arm  = arms(rad, ang01, t) * ARM_GLOW;
    float star = stars(rad, ang01, t, (px.x + px.y) * 0.5) * STAR_GLOW;

    // Collapse wave: a ring that expands out of the body and dies.
    float wp   = fract(t / WAVE_PERIOD);
    float wave = smoothstep(0.055, 0.0, abs(rad - wp * 0.72)) * (1.0 - wp);

    // Event horizon: keyed on the blurred alpha, so the ring follows the sprite
    // outline instead of a circle.
    float horizon = smoothstep(0.16, 0.38, reach) * smoothstep(0.74, 0.44, reach);
    float edge    = clamp(1.0 - rimNbr, 0.0, 1.0);   // 1 just inside the silhouette

    if (aHere > 0.5) {
        // A window into deep space, not a tinted creature.
        vec3 body = mix(here.rgb, VOID_DEEP, 0.93);

        // Drifting nebula: two layers at different speeds so it never sits still.
        float n1 = fbm(v_TexCoord * 4.0 + vec2( t * 0.05, -t * 0.04));
        float n2 = fbm(v_TexCoord * 8.0 - vec2( t * 0.03,  t * 0.06));
        body += mix(COSMIC_BLUE, COSMIC_VIOLET, n2) * pow(n1, 2.2) * 1.25;

        // The disc keeps spiralling behind the silhouette, and the stars with it.
        body += mix(COSMIC_BLUE, COSMIC_VIOLET, 0.65) * arm * 0.45;
        body += STAR_COLOR * star * 0.65;
        body += mix(COSMIC_BLUE, COSMIC_VIOLET, 0.5) * wave * 0.40;

        // Light does not leave: the last pixels before the outline go dark, and
        // only a thin violet bleed survives.
        body *= 1.0 - 0.55 * edge;
        body += COSMIC_VIOLET * edge * 0.22;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        if (reach < 0.03) discard;
        float life  = smoothstep(0.0, MARGIN_FADE, reach);
        float near  = smoothstep(0.0, 0.10, reach);
        float armA  = arm * life;
        float starA = star * near;
        float auraI = max(max(armA * 0.80, starA),
                          max(horizon * 0.85, wave * 0.55)) * VOID_GLOW;
        // The void itself is faintly there between the arms.
        auraI = max(auraI, reach * 0.07);
        if (auraI < 0.02) discard;

        vec3 col = mix(VOID_DEEP, COSMIC_BLUE, life * 0.75);
        col = mix(col, COSMIC_VIOLET, arm);
        col = mix(col, COSMIC_VIOLET + vec3(0.20, 0.10, 0.10), horizon);
        col = mix(col, mix(COSMIC_BLUE, COSMIC_VIOLET, 0.4), wave);
        col = mix(col, STAR_COLOR, min(star, 0.9));
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
