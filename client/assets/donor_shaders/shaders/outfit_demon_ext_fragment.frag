// Demonic Wrath (EXTENDED) fragment - a menacing, blood-red demon effect.
//   - Body: a charred near-black shadow of the character, cracked by BRANCHING
//     HELLFIRE VEINS made from a ridged-FBM field (not Voronoi) that slowly
//     flows and flares.
//   - A DEMONIC HEARTBEAT (double-beat) throbs through everything at once: the
//     veins, the searing rim, and the aura all swell together.
//   - A searing crimson RIM sits on the silhouette.
//   - CRIMSON HELLFLAMES rise off the body into the margin (directional, upward).
//   Blood/crimson palette, white only in the very hottest cores.
//
// Runs on the composited framebuffer (already colored -> no u_Color mask).
// dFdx/dFdy give the texel size. Uses outfit_divine_aura_ext_vertex.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// "Up" in framebuffer space. Flip to vec2(0.0, 1.0) if flames rise from the feet.
const vec2  FLAME_UP    = vec2(0.0, -1.0);

const float BODY_BLACK  = 0.86;  // how charred/black the body gets
const float CRACK_SCALE = 5.0;   // hellfire vein density
const float CRACK_GLOW  = 1.9;   // vein brightness
const float RIM_GLOW    = 1.5;   // searing rim brightness
const float BEAT_SPEED  = 1.5;   // demonic heartbeat tempo
const float FLAME_PX    = 17.0;  // how high the hellflames rise (margin ~25px)
const float AURA_POWER  = 1.3;   // hellflame brightness
const float OUTER_OPAC  = 0.62;  // overall opacity of the flames OUTSIDE the body
const float GLOW_PIXELS = 9.0;   // rim/edge sample reach

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

// Crimson hellfire ramp: 0 = black, mostly deep red, orange/white only at the top.
vec3 hellfire(float x)
{
    x = clamp(x, 0.0, 1.0);
    vec3 c = mix(vec3(0.0),            vec3(0.45, 0.0, 0.0), smoothstep(0.00, 0.35, x));
    c      = mix(c,                    vec3(1.0, 0.08, 0.0), smoothstep(0.35, 0.66, x));
    c      = mix(c,                    vec3(1.0, 0.45, 0.08), smoothstep(0.66, 0.88, x));
    c      = mix(c,                    vec3(1.0, 0.90, 0.65), smoothstep(0.88, 1.00, x));
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

    // Demonic heartbeat: two quick beats, then rest. `throb` swells everything.
    float bc = mod(t * BEAT_SPEED, 6.2831);
    float beat = pow(max(0.0, sin(bc * 2.0)), 8.0) + 0.55 * pow(max(0.0, sin(bc * 2.0 - 0.8)), 6.0);
    float throb = 0.7 + 0.5 * beat;

    // Symmetric edge field (for the searing rim).
    float aSum = aHere;
    float cnt = 1.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (GLOW_PIXELS * 0.5)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  GLOW_PIXELS).a;
        cnt += 2.0;
    }
    float blurA = aSum / cnt;

    if (aHere > 0.5) {
        // Charred shadow body.
        float lum = dot(here.rgb, vec3(0.299, 0.587, 0.114));
        vec3 body = mix(here.rgb, vec3(0.03, 0.01, 0.01), BODY_BLACK);

        // Branching hellfire veins from a slowly-flowing ridged-FBM field.
        vec2 cuv = v_TexCoord * CRACK_SCALE + FLAME_UP * (t * 0.15);
        cuv += 0.35 * vec2(fbm(cuv * 0.7 + t * 0.10), fbm(cuv * 0.7 + 5.0)); // domain warp
        float r = fbm(cuv);
        r = 1.0 - abs(2.0 * r - 1.0);          // ridge lines
        float veins = pow(r, 4.0);             // sharp branching filaments
        float heatVal = veins * throb * (0.7 + 0.3 * lum);
        body += hellfire(heatVal) * CRACK_GLOW;

        // Inner infernal bleed + searing rim, both throbbing.
        body += vec3(0.5, 0.03, 0.0) * throb * 0.12;
        float innerRim = clamp(1.0 - blurA, 0.0, 1.0);
        body += hellfire(0.7 + 0.3 * throb) * innerRim * RIM_GLOW;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Crimson hellflames rising: look DOWN toward the body for fuel (a tongue
        // rises where the body is below). Also look UP: if there is body ABOVE
        // this pixel, it is hanging BELOW the character -> suppress it, so the red
        // stops pooling under the feet where it hurt readability.
        float fuel = 0.0;
        float aboveBody = 0.0;
        for (int k = 1; k <= 12; k++) {
            float frac = float(k) / 12.0;
            float off = frac * FLAME_PX * px.y;
            fuel      = max(fuel,      texture2D(u_Tex0, v_TexCoord - FLAME_UP * off).a * (1.0 - frac));
            aboveBody = max(aboveBody, texture2D(u_Tex0, v_TexCoord + FLAME_UP * off).a);
        }
        float belowMask = 1.0 - clamp(aboveBody, 0.0, 1.0); // 0 under the feet

        // Thin, wispy tongues: driven mostly by the rising turbulence, and faded
        // toward the tips (multiply by fuel) so they are translucent, not solid.
        float smoke = 0.5 + 0.5 * fbm(vec2(v_TexCoord.x * 10.0, v_TexCoord.y * 5.0) + FLAME_UP * (t * 2.2));
        float flame = smoothstep(0.42, 0.85, fuel * (0.20 + 1.25 * smoke)) * fuel;
        float sideGlow = blurA * 0.14; // very faint crimson wreath on the sides
        float auraI = max(flame, sideGlow) * throb * AURA_POWER * belowMask * OUTER_OPAC;
        if (auraI < 0.02) discard;

        float hot = clamp(max(fuel, blurA) * 1.4, 0.0, 1.0);
        vec3 col = hellfire(0.22 + 0.5 * hot); // deep red outside -> hotter near body
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
