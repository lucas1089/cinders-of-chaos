// Zapdos Lightning (EXTENDED) fragment - yellow lightning bolts radiating OUT of
// the character into the margin. Built from scratch on a polar-bolt idea:
//   - Around the body center, N radial BOLTS zig-zag outward; their angle jitters
//     with radius (jagged) and RESHAPES in fast discrete electric frames, with
//     each bolt flickering on/off and energy racing along its length.
//   - The same bolt field crackles THROUGH the charged yellow body and continues
//     seamlessly OUT past the silhouette into the 25px margin (fading with reach).
//   - Random DISCHARGE FLASHES light the whole thing up now and then.
//   No fire/aura-noise reuse - a different technique. Uses outfit_divine_aura_ext_vertex.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3  YELLOW    = vec3(1.00, 0.90, 0.15);
const vec3  WHITE_HOT = vec3(1.00, 1.00, 0.85);

const float BOLT_COUNT   = 11.0; // number of radial bolts
const float BOLT_WIDTH   = 0.055;// angular half-thickness of a bolt
const float JAG          = 1.5;  // zig-zag amount
const float JAG_FREQ     = 11.0; // zig-zag detail along the radius
const float FLICKER_RATE = 16.0; // electric reshape/flicker speed
const float BOLT_GLOW    = 1.9;  // bolt brightness
const float REACH_PX     = 20.0; // how far bolts reach into the margin

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

// Radial lightning field around a center. Returns bolt intensity at p.
float boltField(vec2 p, float t)
{
    float rad = length(p);
    float ang = atan(p.y, p.x) * 0.159155 + 0.5;      // 0..1 around the center
    float tq  = floor(t * FLICKER_RATE);              // discrete electric frames

    // Jitter the bolt angle as it travels out -> jagged bolt; reshapes per frame.
    float n = fbm(vec2(rad * JAG_FREQ, tq * 2.3 + 11.0)) - 0.5;
    float a = fract(ang * BOLT_COUNT + n * JAG);
    float core = smoothstep(BOLT_WIDTH, 0.0, abs(a - 0.5));

    // Each bolt flickers on/off, and energy races along its length.
    float which = floor(ang * BOLT_COUNT + 0.5);
    float on = step(0.42, hash2(vec2(which, tq)).x);
    float race = 0.55 + 0.45 * sin(rad * 42.0 - t * 34.0);

    return core * on * race;
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;
    vec4 here = texture2D(u_Tex0, v_TexCoord);
    float aHere = here.a;

    // Bolt-reach field: alpha blurred over ~REACH_PX so bolts fade out into the
    // margin and stay anchored to the body.
    float aSum = aHere;
    float cnt = 1.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (REACH_PX * 0.5)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  REACH_PX).a;
        cnt += 2.0;
    }
    float reach = aSum / cnt;

    // Bolts radiate from the framebuffer center (character is centered in it).
    vec2 p = v_TexCoord - 0.5;
    float bolt = boltField(p, t);

    // Random discharge flashes.
    float flash = pow(hash2(vec2(floor(t * 3.0), 7.0)).x, 6.0);
    float glowPulse = 0.85 + 0.15 * sin(t * 30.0) + flash * 0.6;

    if (aHere > 0.5) {
        // Charged yellow body with crackling arcs coursing through it.
        vec3 body = mix(here.rgb, YELLOW, 0.45) * 0.85;
        body += mix(YELLOW, WHITE_HOT, bolt) * bolt * BOLT_GLOW;
        body += YELLOW * 0.12 * glowPulse;             // electric haze
        gl_FragColor = vec4(clamp(body * glowPulse, 0.0, 1.0), here.a);
    } else {
        // Bolts continue OUT into the margin, fading with reach; faint yellow halo.
        float b = bolt * reach;
        float halo = reach * 0.18;
        float auraI = (b * BOLT_GLOW + halo) * glowPulse;
        if (auraI < 0.02) discard;
        vec3 col = mix(YELLOW, WHITE_HOT, bolt);
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
