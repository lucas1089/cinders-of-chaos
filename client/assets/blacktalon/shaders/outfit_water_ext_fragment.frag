// Aqua Depths (EXTENDED) fragment - submerged character with clean round BUBBLES.
//   - Body: aquatic tint + dancing light CAUSTICS + a gentle REFRACTION wobble.
//   - Bubbles: a grid of bubbles that rise CONTINUOUSLY (no per-cycle teleport,
//     so nothing pops/cuts), each swaying sideways with its own size. They are
//     drawn the SAME way on the body and just off it, and fade out over a WIDE
//     range in the margin, so they dissolve smoothly instead of clipping.
//   Uses outfit_divine_aura_ext_vertex.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3  WATER_DEEP  = vec3(0.05, 0.35, 0.60);
const vec3  WATER_LIGHT = vec3(0.55, 0.88, 1.00);
const vec3  FOAM        = vec3(0.95, 1.00, 1.00);

const float REACH_PX     = 22.0; // aura reach into the margin
const float RIM_PX       = 3.0;  // water-surface rim on the silhouette
const float WOBBLE       = 0.006;// refraction wobble amount
const float CAUSTIC_STR  = 0.32; // caustic brightness on the body

// Bubbles (grid-cell units).
const float BUBBLE_SCALE = 12.0; // density (higher = smaller/more)
const float RISE         = 1.1;  // rise speed. Make negative if they fall.
const float SWAY         = 0.26; // sideways sway amount
const float BUB_MIN      = 0.07; // smallest bubble radius
const float BUB_MAX      = 0.17; // largest bubble radius
const float RING_W       = 0.045;// outline thickness
const float MARGIN_FADE  = 0.30; // how gradually bubbles dissolve in the margin
const float WIDE_PX      = 22.0; // radius used to find the body's center of mass
const float CIRC_LO      = 0.10; // centrality range: below -> few bubbles
const float CIRC_HI      = 0.40; // centrality range: above -> full bubbles
const float WATER_GLOW    = 1.2;

vec2 hash2(vec2 p)
{
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

float caustic(vec2 uv, float t)
{
    vec2 p = uv * 5.0;
    float c = sin(p.x * 1.7 + t * 1.2) + sin(p.y * 1.9 - t * 1.5)
            + sin((p.x + p.y) * 1.3 + t * 0.9) + sin((p.x - p.y) * 1.5 - t);
    c *= 0.25;
    return pow(0.5 + 0.5 * c, 4.0);
}

// Continuously rising bubbles. Returns ring; `hi` = specular highlight.
float bubbles(vec2 uv, float t, out float hi)
{
    float ring = 0.0; hi = 0.0;
    vec2 gp = uv * BUBBLE_SCALE;
    gp.y -= t * RISE;                       // smooth, continuous rise (no teleport)
    vec2 base = floor(gp);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 cell = base + vec2(float(x), float(y));
            vec2 r = hash2(cell);
            float present = step(0.40, r.x);

            // Wandering path: two sway waves at per-bubble frequencies + a small
            // vertical jitter -> each bubble drifts on its own random-ish path.
            float cx = cell.x + 0.5
                     + SWAY * sin(t * (0.9 + 0.6 * r.y) + r.x * 6.2831)
                     + SWAY * 0.6 * sin(t * (1.7 + r.x) + r.y * 6.2831);
            float cy = cell.y + 0.5 + 0.16 * sin(t * (1.1 + r.x) + r.y * 6.2831);
            vec2 c = vec2(cx, cy);
            float size = mix(BUB_MIN, BUB_MAX, r.y);

            vec2 rel = gp - c;
            float d = length(rel);
            ring = max(ring, smoothstep(RING_W, 0.0, abs(d - size)) * present);
            hi   = max(hi, smoothstep(size * 0.26, 0.0, length(rel - vec2(-0.30, -0.32) * size)) * present);
        }
    }
    return ring;
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;

    vec2 wob = WOBBLE * vec2(sin(v_TexCoord.y * 22.0 + t * 2.0), cos(v_TexCoord.x * 22.0 + t * 1.6));
    vec4 here = texture2D(u_Tex0, v_TexCoord + wob);
    float aHere = here.a;

    // Reach (aura) + tight rim from a plain blur.
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

    float hi;
    float ring = bubbles(v_TexCoord, t, hi);

    // Concentrate the bubbles toward the body's CENTER OF MASS. A wide alpha blur
    // peaks in the middle of the character (wherever it sits in the framebuffer),
    // so this needs no fixed center. A 0.12 floor guarantees bubbles never vanish.
    float central = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7853981;
        vec2 d = vec2(cos(a), sin(a));
        central += texture2D(u_Tex0, v_TexCoord + d * px * (WIDE_PX * 0.6)).a;
        central += texture2D(u_Tex0, v_TexCoord + d * px *  WIDE_PX).a;
    }
    central /= 16.0;
    float circ = 0.12 + 0.88 * smoothstep(CIRC_LO, CIRC_HI, central);
    ring *= circ;
    hi   *= circ;

    if (aHere > 0.5) {
        // Submerged body: aquatic tint + caustics + rim + bubbles over it.
        vec3 body = mix(here.rgb, WATER_DEEP, 0.45);
        body += WATER_LIGHT * caustic(v_TexCoord, t) * CAUSTIC_STR;
        float rim = clamp(1.0 - rimNbr, 0.0, 1.0);
        body += WATER_LIGHT * rim * 0.5;

        body = mix(body, WATER_LIGHT, ring * 0.85);
        body += FOAM * hi;
        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Bubbles drifting just off the body, dissolving smoothly + faint glow.
        float life = smoothstep(0.0, MARGIN_FADE, reach); // wide, gradual -> no hard cut
        float bub  = (ring + hi * 1.3) * life;
        float glow = reach * 0.16;
        float auraI = max(glow, bub) * WATER_GLOW;
        if (auraI < 0.02) discard;

        vec3 col = mix(WATER_DEEP, WATER_LIGHT, max(reach, ring));
        col = mix(col, WATER_LIGHT, ring);
        col = mix(col, FOAM, hi);
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
