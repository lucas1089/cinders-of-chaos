// Dark/Discord Boost (outfit) fragment - "edgy/dark" cosmetic.
// Darkens the character ~70% and drifts soft dark-violet ENERGY ORBS across the
// body. The orb core is a DEEP VIOLET (not pure black) and its halo is a MUTED
// violet of the same family, so core and halo blend cohesively instead of
// clashing. Kept subtle/atmospheric.
//
// Seamless + attached to the body: v_LocalPos is (a_Vertex - u_Center), so it is
// continuous across sprite tiles AND walks with the creature. The 3x3 neighbour
// scan makes cell borders seamless.
// BlackTalon MMORPG

uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_LocalPos;
uniform sampler2D u_Tex0;
uniform float u_Time;

// --- Look controls ---
const float DARKNESS       = 0.70; // how much to darken the outfit (0..1)
const vec3  TINT           = vec3(0.16, 0.05, 0.28); // dark violet in the shadows
const float TINT_STRENGTH  = 0.22; // 0 = pure black shadows, 1 = full violet

// --- Orb field (body-centered pixels) ---
const float SCALE          = 0.030; // orb spacing/size vs body. lower = bigger/fewer.
const float SPHERE_SPEED   = 0.55;  // drift speed

// Core + halo radii (cell units). Big blur + close colors keep it cohesive.
const float CORE_RADIUS    = 0.42;  // orb core size
const float CORE_BLUR      = 0.85;  // 0 = crisp core, 1 = very soft core
const float GLOW_RADIUS    = 0.85;  // how far the halo reaches (> CORE_RADIUS)

const vec3  ORB_DARK       = vec3(0.05, 0.01, 0.11); // deep violet core (not black)
const float CORE_STRENGTH  = 0.70;  // how strongly the core takes over (< 1 = softer)

const vec3  HALO_COLOR     = vec3(0.30, 0.10, 0.52); // muted violet glow (not neon)
const float HALO_STRENGTH  = 0.30;  // subtle halo brightness

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main()
{
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor  = texture2D(u_Tex0, v_TexCoord2);

    if (baseColor.a < 0.01) discard;

    // Standard outfit color application (head/body/legs/feet via the mask).
    if (texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if (texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if (texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }

    vec3 col = baseColor.rgb;

    // 1) Darken ~70%, with a faint dark-violet life in the shadows.
    col *= (1.0 - DARKNESS);
    col = mix(col, TINT, TINT_STRENGTH);

    // 2) Dark-violet energy orbs (deep core + soft same-family halo).
    vec2 p = v_LocalPos * SCALE;
    vec2 cellBase = floor(p);
    vec2 f = p - cellBase;

    float inner = CORE_RADIUS * (1.0 - CORE_BLUR); // solid core radius
    float core = 0.0; // core accumulation
    float glow = 0.0; // broad falloff (core + halo)
    for (int gy = -1; gy <= 1; gy++) {
        for (int gx = -1; gx <= 1; gx++) {
            vec2 g = vec2(float(gx), float(gy));
            vec2 cellId = cellBase + g;

            float r1 = hash(cellId);
            float r2 = hash(cellId + 3.17);

            vec2 center = g + vec2(0.5) + 0.3 * vec2(sin(u_Time * SPHERE_SPEED + r1 * 6.2831),
                                                     cos(u_Time * SPHERE_SPEED + r2 * 6.2831));
            float d = distance(f, center);
            core += smoothstep(CORE_RADIUS, inner, d);
            glow += smoothstep(GLOW_RADIUS, inner, d);
        }
    }
    core = clamp(core, 0.0, 1.0);
    glow = clamp(glow, 0.0, 1.0);
    float halo = clamp(glow - core, 0.0, 1.0); // ring between core and glow

    // Deep-violet core (soft), then a gentle same-family halo. Low contrast.
    col = mix(col, ORB_DARK, core * CORE_STRENGTH);
    col += HALO_COLOR * halo * HALO_STRENGTH;
    col = clamp(col, 0.0, 1.0);

    gl_FragColor = vec4(col, baseColor.a);
}
