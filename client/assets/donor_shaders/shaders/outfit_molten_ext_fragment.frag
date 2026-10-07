// Molten Demon (EXTENDED) fragment - a volcanic / hellfire outfit effect.
//   - The body becomes a dark CHARRED CRUST split by GLOWING LAVA CRACKS
//     (blackbody heat ramp: dark red -> orange -> yellow -> white-hot core).
//   - A DEMONIC HEARTBEAT makes the magma swell (two quick beats, then rest).
//   - Rising EMBERS flicker up over the body and the aura.
//   - A flickering FIRE AURA licks OUTWARD beyond the silhouette (extended path,
//     into the 25px padded margin), rising like flame.
//
// Runs on the composited framebuffer (already colored -> no u_Color mask). Edge
// distance from an alpha blur (dFdx/dFdy). Uses outfit_divine_aura_ext_vertex.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3  CRUST       = vec3(0.05, 0.03, 0.03); // charred rock
const float CRUST_MIX   = 0.82;  // how charred the body gets

// Lava cracks.
const float CELL_SCALE  = 8.0;
const float CELL_SPEED  = 0.25;  // crust shifts slowly
const float CRACK_WIDTH = 0.10;  // fissure thickness
const float HEAT_POWER  = 1.6;   // magma brightness

// Demonic heartbeat.
const float BEAT_SPEED  = 1.6;

// Embers.
const float EMBER_SCALE = 16.0;
const float EMBER_RISE  = 0.6;
const float EMBER_GLOW  = 1.1;

// Fire aura.
const float GLOW_PIXELS = 12.0;
const float AURA_POWER  = 1.9;

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

// Blackbody-ish heat ramp: 0 = black rock, 1 = white hot.
vec3 heat(float x)
{
    x = clamp(x, 0.0, 1.0);
    vec3 c = mix(vec3(0.0),            vec3(0.55, 0.02, 0.0), smoothstep(0.00, 0.30, x));
    c      = mix(c,                    vec3(1.0, 0.35, 0.02), smoothstep(0.30, 0.60, x));
    c      = mix(c,                    vec3(1.0, 0.82, 0.20), smoothstep(0.60, 0.85, x));
    c      = mix(c,                    vec3(1.0, 0.98, 0.85), smoothstep(0.85, 1.00, x));
    return c;
}

// Voronoi 1st/2nd distance gap -> ~0 on cell walls (the cracks).
float cellEdge(vec2 uv, float t)
{
    vec2 g = floor(uv), f = fract(uv);
    float d1 = 8.0, d2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 lat = vec2(float(x), float(y));
            vec2 o = hash2(g + lat);
            vec2 pt = lat + 0.5 + 0.4 * sin(t + 6.2831 * o);
            float d = length(pt - f);
            if (d < d1) { d2 = d1; d1 = d; }
            else if (d < d2) { d2 = d; }
        }
    }
    return d2 - d1;
}

// Rising, flickering ember.
float embers(vec2 uv, float t)
{
    vec2 sp = uv * EMBER_SCALE;
    sp.y += t * EMBER_RISE * EMBER_SCALE;
    vec2 cell = floor(sp), f = fract(sp);
    vec2 r = hash2(cell);
    vec2 c = vec2(0.5) + 0.3 * vec2(sin(t * 2.0 + r.x * 6.2831), cos(t * 1.5 + r.y * 6.2831));
    float d = distance(f, c);
    float tw = pow(0.5 + 0.5 * sin(t * 5.0 + r.x * 6.2831), 4.0);
    return smoothstep(0.11, 0.0, d) * tw;
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;

    vec4 here = texture2D(u_Tex0, v_TexCoord);
    float aHere = here.a;

    // Aura field from an alpha blur.
    float aSum = aHere;
    float cnt  = 1.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (GLOW_PIXELS * 0.35)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (GLOW_PIXELS * 0.70)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  GLOW_PIXELS).a;
        cnt  += 3.0;
    }
    float blurA = aSum / cnt;

    // Demonic heartbeat: two quick beats, then a rest.
    float bc = mod(t * BEAT_SPEED, 6.2831);
    float beat = pow(max(0.0, sin(bc * 2.0)), 8.0) + 0.5 * pow(max(0.0, sin(bc * 2.0 - 0.8)), 6.0);

    // Flame turbulence rising upward.
    float flame = fbm(v_TexCoord * vec2(8.0, 5.0) + vec2(0.0, -t * 1.6));
    float ember = embers(v_TexCoord, t);

    if (aHere > 0.5) {
        // Charred crust.
        vec3 body = mix(here.rgb, CRUST, CRUST_MIX);

        // Lava cracks, hottest at the crack core, flickering + pulsing on the beat.
        float e = cellEdge(v_TexCoord * CELL_SCALE, t * CELL_SPEED);
        float crack = smoothstep(CRACK_WIDTH, 0.0, e);
        float heatVal = crack * (0.55 + 0.45 * flame) * (0.7 + 0.6 * beat);
        body += heat(heatVal) * HEAT_POWER;

        // Rising embers.
        body += heat(0.7 + 0.3 * ember) * ember * EMBER_GLOW;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Fire aura: flame-shaped (blurA broken up by rising turbulence), flicker
        // + heartbeat. Blackbody colored, hotter near the body. Alpha follows the
        // brightness so there is no dark halo.
        float fire = blurA * (0.35 + 0.9 * flame);
        float auraI = (fire * AURA_POWER + ember * blurA * 1.4) * (0.8 + 0.4 * beat);
        if (auraI < 0.03) discard;

        float hotness = clamp(fire * 1.4, 0.0, 1.0); // near body = hotter/whiter
        vec3 col = heat(0.35 + 0.55 * hotness);
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
