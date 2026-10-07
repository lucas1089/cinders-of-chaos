// Alien Bioluminescence (EXTENDED) fragment - a living-alien outfit effect.
//   - Dark alien hide crawling with GLOWING CELL VEINS (domain-warped Voronoi,
//     so the membrane writhes) in an IRIDESCENT green->cyan->violet shimmer, with
//     an ENERGY PULSE coursing through the network.
//   - HOLOGRAM: sweeping scanline + chromatic (RGB) split + rare glitch tears.
//   - Rising BIOLUMINESCENT SPORES drifting up over the body and the aura.
//   - A toxic AURA breathes OUTWARD beyond the silhouette (extended path, 25px).
//
// Runs on the composited framebuffer (already colored -> no u_Color mask). Edge
// distance from an alpha blur (dFdx/dFdy). Uses outfit_divine_aura_ext_vertex.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Iridescent alien palette (cycled green -> cyan -> violet).
const vec3  ALIEN_GREEN  = vec3(0.35, 1.00, 0.45);
const vec3  ALIEN_CYAN   = vec3(0.30, 1.00, 0.85);
const vec3  ALIEN_VIOLET = vec3(0.62, 0.30, 1.00);
const vec3  ALIEN_DARK   = vec3(0.03, 0.05, 0.06);

const float BODY_DARKEN  = 0.62;

// Cell veins + writhe + pulse.
const float CELL_SCALE   = 9.0;
const float CELL_SPEED   = 0.6;
const float WARP_AMOUNT  = 0.09;  // membrane writhe (0 = rigid cells)
const float VEIN_WIDTH   = 0.06;
const float VEIN_GLOW    = 1.7;
const float PULSE_SPEED  = 3.0;

// Iridescence.
const float IRID_SPEED   = 0.25;
const float IRID_FREQ    = 0.8;

// Hologram.
const float SCAN_FREQ    = 42.0;
const float SCAN_SPEED   = 5.0;
const float SCAN_STR     = 0.35;
const float CHROMA_SPLIT = 1.3;
const float GLITCH_RARITY= 0.90;
const float GLITCH_AMOUNT= 0.05;

// Spores.
const float SPORE_SCALE  = 14.0;
const float SPORE_RISE   = 0.35;
const float SPORE_GLOW   = 0.9;

// Toxic aura.
const float GLOW_PIXELS  = 11.0;
const float AURA_POWER   = 1.6;

vec2 hash2(vec2 p)
{
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// Cyclic green -> cyan -> violet -> green iridescence.
vec3 irid(float x)
{
    x = fract(x);
    if (x < 0.3333)      return mix(ALIEN_GREEN,  ALIEN_CYAN,   x / 0.3333);
    else if (x < 0.6666) return mix(ALIEN_CYAN,   ALIEN_VIOLET, (x - 0.3333) / 0.3333);
    else                 return mix(ALIEN_VIOLET, ALIEN_GREEN,  (x - 0.6666) / 0.3334);
}

float cellEdge(vec2 uv, float t)
{
    vec2 g = floor(uv);
    vec2 f = fract(uv);
    float d1 = 8.0, d2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 lat = vec2(float(x), float(y));
            vec2 o = hash2(g + lat);
            vec2 pt = lat + 0.5 + 0.42 * sin(t + 6.2831 * o);
            float d = length(pt - f);
            if (d < d1) { d2 = d1; d1 = d; }
            else if (d < d2) { d2 = d; }
        }
    }
    return d2 - d1;
}

// Rising, twinkling bioluminescent motes.
float spores(vec2 uv, float t)
{
    vec2 sp = uv * SPORE_SCALE;
    sp.y += t * SPORE_RISE * SPORE_SCALE; // drift upward
    vec2 cell = floor(sp);
    vec2 f = fract(sp);
    vec2 r = hash2(cell);
    vec2 c = vec2(0.5) + 0.32 * vec2(sin(t * 1.3 + r.x * 6.2831), cos(t + r.y * 6.2831));
    float d = distance(f, c);
    float tw = pow(0.5 + 0.5 * sin(t * 3.0 + r.x * 6.2831), 3.0);
    return smoothstep(0.14, 0.0, d) * tw;
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;

    // Rare horizontal glitch tear.
    float bandId = floor(v_TexCoord.y * 20.0 - t * 3.0);
    float glitch = step(GLITCH_RARITY, hash2(vec2(bandId, 1.3)).x);
    float jitter = glitch * (hash2(vec2(bandId, 3.7)).x - 0.5) * GLITCH_AMOUNT;
    vec2 uv = v_TexCoord + vec2(jitter, 0.0);

    vec4 here = texture2D(u_Tex0, uv);
    float aHere = here.a;

    // Edge/aura field from an alpha blur.
    float aSum = aHere;
    float cnt  = 1.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, uv + dir * px * (GLOW_PIXELS * 0.35)).a;
        aSum += texture2D(u_Tex0, uv + dir * px * (GLOW_PIXELS * 0.70)).a;
        aSum += texture2D(u_Tex0, uv + dir * px *  GLOW_PIXELS).a;
        cnt  += 3.0;
    }
    float blurA = aSum / cnt;

    float hue = (v_TexCoord.x + v_TexCoord.y) * IRID_FREQ + t * IRID_SPEED;
    float spore = spores(v_TexCoord, t);

    if (aHere > 0.5) {
        // Scanline drives the chromatic split.
        float scan = pow(0.5 + 0.5 * sin(v_TexCoord.y * SCAN_FREQ - t * SCAN_SPEED), 10.0);
        float splitAmt = px.x * (CHROMA_SPLIT + scan * CHROMA_SPLIT * 3.0);
        float rC = texture2D(u_Tex0, uv + vec2(splitAmt, 0.0)).r;
        float bC = texture2D(u_Tex0, uv - vec2(splitAmt, 0.0)).b;
        vec3 src = vec3(rC, here.g, bC);

        // Dark alien hide + faint iridescent sheen.
        float lum = dot(src, vec3(0.299, 0.587, 0.114));
        vec3 body = mix(src, ALIEN_DARK, BODY_DARKEN);
        body += irid(hue + 0.5) * lum * 0.12;

        // Writhing, iridescent cell veins + energy pulse.
        vec2 warp = WARP_AMOUNT * vec2(sin(v_TexCoord.y * 7.0 + t * 0.8),
                                       cos(v_TexCoord.x * 7.0 + t * 0.7));
        float e = cellEdge((v_TexCoord + warp) * CELL_SCALE, t * CELL_SPEED);
        float veins = smoothstep(VEIN_WIDTH, 0.0, e);
        float pulse = pow(0.5 + 0.5 * sin((v_TexCoord.x + v_TexCoord.y) * 6.0 - t * PULSE_SPEED), 3.0);
        body += irid(hue) * veins * VEIN_GLOW * (0.45 + 1.0 * pulse);

        // Hologram scan + glitch flash + rising spores.
        body += ALIEN_CYAN * scan * SCAN_STR;
        body += ALIEN_CYAN * glitch * 0.20;
        body += irid(hue + 0.25) * spore * SPORE_GLOW;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Toxic aura breathing outward, with floating spores.
        float wob = 0.65 + 0.35 * sin(v_TexCoord.y * 18.0 - t * 3.0 + v_TexCoord.x * 13.0);
        float auraI = blurA * wob * AURA_POWER;
        auraI += spore * blurA * 1.6; // spores glow in the near-aura
        if (auraI < 0.02) discard;
        // Fully iridescent aura: cycles green -> cyan -> violet with the body.
        // A small outward offset makes the hue drift across the aura's depth.
        vec3 col = irid(hue + (1.0 - blurA) * 0.20);
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
