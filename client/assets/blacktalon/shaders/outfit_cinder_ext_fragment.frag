// Cinderheart (EXTENDED) - the creature is a SHELL WITH A FIRE INSIDE IT.
//
// No veins, no cracks, no cell network, no seams: those all read as the Alien
// Bioluminescence membrane. What burns here is a real flame column, rendered
// INSIDE the silhouette and clipped to it, so you are looking at fire churning
// behind a dark shell instead of glowing lines drawn on a creature.
//
//   - INTERIOR MASK: the flames are multiplied by how DEEP inside the silhouette
//     the pixel is (from the blurred alpha), so the outer few pixels of the body
//     stay a solid dark shell and the fire never touches the outline. That mask is
//     what sells "inside": no other shader here draws into the interior only.
//   - FLAME COLUMN: turbulence stretched tall, advected upward and domain-warped
//     by a slower field so tongues lick, split and curl; the lit threshold RISES
//     with height, so tongues taper off as they climb instead of filling the body.
//   - REAL FLAME PHYSICS IN THE PALETTE: the base of the fire is BLUE (hottest),
//     going orange as it rises, and the top cools into drifting ash haze. The
//     colour tells you where the fuel is.
//   - BACKLIT SHELL: where a tongue presses against the shell from the inside, the
//     shell itself glows ember - the light source is behind the crust, not on it.
//   - REFRACTIVE HEAT HAZE: the body is read through a rising turbulence OFFSET,
//     so the creature's pixels shimmer. Alpha comes from the unwarped sample, so
//     the silhouette never wobbles.
//   - OUTSIDE IS ALMOST NOTHING: a thin ember heat-glow hugging the outline plus
//     sparse rising embers. No tongues, no white, no dark - the drama is inside,
//     which is the whole point of the effect.
//   Uses outfit_divine_aura_ext_vertex.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Palette is overridable so a tinted variant can reuse this file by prepending
// its own #defines (see scripts/gen_shader_variants.js).
#ifndef SHELL_COLOR
#define SHELL_COLOR  vec3(0.07, 0.04, 0.03)
#endif
#ifndef EMBER_COLOR
#define EMBER_COLOR  vec3(1.00, 0.32, 0.04)
#endif
#ifndef FLAME_COLOR
#define FLAME_COLOR  vec3(1.00, 0.68, 0.18)
#endif
#ifndef CORE_COLOR
#define CORE_COLOR   vec3(1.00, 0.94, 0.72)
#endif
#ifndef ENERGY_COLOR
#define ENERGY_COLOR vec3(0.30, 0.62, 1.00)
#endif
#ifndef ASH_COLOR
#define ASH_COLOR    vec3(0.20, 0.17, 0.16)
#endif

// "Up" in framebuffer space, same convention as outfit_demon_ext_fragment.
const vec2  UP           = vec2(0.0, -1.0);

const float GLOW_PX      = 8.0;   // alpha blur reach (interior mask + outline glow)
const float SHELL_LO     = 0.55;  // blurred alpha where the shell ends...
const float SHELL_HI     = 0.92;  // ...and the interior is fully open to the fire
const float SHELL_DARK   = 0.76;  // how charred the shell is

// Flame column inside the body.
const float FIRE_BASE    = 0.88;  // quad y where the fire is fed from
const float FIRE_TOP     = 0.16;  // quad y where it has burnt out
const float FIRE_W       = 9.0;   // horizontal turbulence frequency
const float FIRE_H       = 4.2;   // vertical frequency (lower = taller tongues)
const float FIRE_SPEED   = 1.90;  // how fast the column rises
const float FIRE_CURL    = 0.55;  // licking / splitting of the tongues
const float FIRE_TAPER   = 0.30;  // how much harder it is to stay lit up high
const float BLUE_BASE    = 0.20;  // height below which the flame runs blue
const float ASH_TOP      = 0.62;  // height above which it cools into ash haze
// The fire is TRANSLUCENT: it never fully replaces the creature underneath, so
// the sprite still reads through the flames instead of becoming a bright blob.
const float FIRE_OPACITY = 0.62;
const float FIRE_WARM    = 0.50;  // how far up the ramp it may go (1 = full yellow)
const float HEART_GLOW   = 0.30;  // brightest cores. Orange, never white.

const float HAZE_PX      = 2.4;   // heat-shimmer displacement, in pixels
const float RIM_GLOW     = 0.55;  // ember rim on the silhouette

// Outside: heat glow + sparks only.
const float EMBER_SCALE  = 12.0;
const float EMBER_RISE   = 0.50;
const float EMBER_PX     = 1.25;  // ember radius, in PIXELS
const float MARGIN_OPAC  = 0.62;

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

// Rising sparks. Sized in PIXELS via pxLen, so an ember is the same crisp dot at
// any zoom instead of scaling with the grid.
float embers(vec2 uv, float t, float pxLen)
{
    vec2 gp = uv * EMBER_SCALE + vec2(0.0, t * EMBER_RISE);  // +y scroll = climbing
    vec2 base = floor(gp);
    float acc = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = base + vec2(float(i), float(j));
            vec2 h = hash2(c + 2.9);
            if (h.x < 0.52) continue;                        // sparse
            float drift = 0.30 * sin(t * (1.3 + 2.2 * h.y) + h.x * 6.2831);
            vec2 pos = c + vec2(0.5 + drift, 0.5);
            vec2 rel = (gp - pos) / EMBER_SCALE;             // -> texcoord units
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

    // Height through the fire column: 0 at the fuel, 1 where it has burnt out.
    float h = clamp((FIRE_BASE - uv.y) / max(FIRE_BASE - FIRE_TOP, 1e-3), 0.0, 1.0);

    // The flame column itself. Tall turbulence, advected up, warped by a slower
    // field so the tongues lick and split instead of scrolling like a texture.
    vec2 fuv = vec2(uv.x * FIRE_W, uv.y * FIRE_H) + UP * (t * FIRE_SPEED);
    fuv += FIRE_CURL * vec2(fbm(fuv * 0.45 + vec2(0.0, t * 0.8)),
                            fbm(fuv * 0.40 + 13.0));
    float n = fbm(fuv);
    // The threshold has to sit ABOVE the mean of the fbm, otherwise almost every
    // interior pixel qualifies and the body turns into one solid glowing mass.
    float thr = 0.43 + FIRE_TAPER * h;            // harder to stay lit up high
    float lit = smoothstep(thr, thr + 0.20, n);
    // Second, faster layer -> the brighter heart inside a tongue.
    float n2 = fbm(fuv * 2.1 + UP * (t * 1.1));
    float core = smoothstep(thr + 0.26, thr + 0.44, 0.55 * n + 0.55 * n2);

    if (aHere > 0.5) {
        // How deep inside the silhouette we are. 0 on the shell, 1 in the middle.
        float interior = smoothstep(SHELL_LO, SHELL_HI, blurA);

        // Heat haze: read the sprite through a rising turbulence offset. A warped
        // sample that lands on empty space falls back to the original colour, and
        // the alpha is always the unwarped one, so the outline stays clean.
        vec2 warp = vec2(fbm(uv * 8.0 + UP * (t * 1.30)) - 0.5,
                         fbm(uv * 8.0 + 21.0 + UP * (t * 1.55)) - 0.5)
                    * (HAZE_PX * (0.45 + 0.55 * lit)) * px;
        vec4 w = texture2D(u_Tex0, uv + warp);
        vec3 skin = mix(here.rgb, w.rgb, w.a);

        // The shell: charred, but still the creature - it is what the fire is
        // trapped behind, so it must stay readable.
        vec3 body = mix(skin, SHELL_COLOR, SHELL_DARK);

        // Backlight: a tongue pressed against the shell glows THROUGH it.
        body += EMBER_COLOR * lit * (1.0 - interior) * 0.45;

        // The fire, clipped to the interior. It stays in the same ember/orange
        // band as the rim glow - the white end of the ramp is what blew the middle
        // of the body out into a featureless blob.
        float flame = lit * interior;
        vec3 fire = mix(EMBER_COLOR, FLAME_COLOR, smoothstep(0.0, 0.45, h) * FIRE_WARM);
        fire = mix(fire, ENERGY_COLOR, smoothstep(BLUE_BASE, 0.0, h) * 0.55);  // blue pilot
        fire = mix(fire, ASH_COLOR,    smoothstep(ASH_TOP, 1.0, h) * 0.60);    // cools to ash
        body = mix(body, fire, flame * FIRE_OPACITY);
        // Hearts of the tongues: brighter orange, NOT white.
        body += FLAME_COLOR * core * interior * (1.0 - smoothstep(0.35, 0.85, h)) * HEART_GLOW;

        // Ember rim, so the silhouette keeps an edge against the map.
        float innerRim = clamp(1.0 - blurA, 0.0, 1.0);
        body += EMBER_COLOR * innerRim * RIM_GLOW;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Outside is deliberately quiet: a thin ember heat-glow hugging the
        // outline, plus sparse embers climbing off the body. No tongues, no white.
        float halo  = smoothstep(0.02, 0.42, blurA);
        float spark = embers(uv, t, pxLen) * smoothstep(0.01, 0.30, blurA);

        float auraI = max(halo * 0.22, spark * 0.85) * MARGIN_OPAC;
        if (auraI < 0.02) discard;

        // Ember -> flame only. The ramp never reaches white (that is what washed
        // the outline out) and never reaches ash (that read as a shadow).
        vec3 col = mix(EMBER_COLOR, FLAME_COLOR, min(spark, 1.0) * 0.7 + halo * 0.25);
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
