uniform sampler2D u_Tex0;          // map framebuffer
varying vec2 v_TexCoord;
uniform vec4 u_Color;
uniform vec2 u_Resolution;
uniform float u_Time;
uniform float u_var0;              // fade amount, 0 = off, 1 = full effect

// ============================================================================
// map_thunderstun -- "struck by lightning" disorientation
// ============================================================================
// Meant to sit on ONE player for a few seconds after a boss's lightning
// connects, not on a zone. Four layers, every one of them scaled by u_var0, so
// the effect ROLLS IN and ROLLS OUT instead of snapping on. u_var0 is driven by
// the FADE_SHADERS table in modules/game_shaders/shaders.lua -- the entry there
// is what makes the roll-over readable rather than a jump cut.
//
//   1. FLIP       the view is turned a full 180 degrees, upside down from the
//                 first frame (ROLL_IN below switches this to a gradual roll).
//                 Aspect-corrected: without that, a non-square viewport
//                 visibly squashes while turning.
//   2. STAGGER    two out-of-phase sways plus a per-scanline ripple. This is
//                 the layer that actually sells "cannot walk straight".
//   3. ARCS       short bursts where jagged bolts cross the screen, the frame
//                 blows out white-blue and the image gets kicked sideways.
//   4. NERVE BURN desaturation toward electric blue, deepest during a burst.
//
// GLSL 1.20 (varying / texture2D / attribute) to match every other map shader
// in this folder. Do NOT use in/out or texture() here -- they will not compile.
// ============================================================================

const float ROLL_HALF_TURNS = 1.0;    // 1.0 = fully upside down
// 0.0 = already flipped on the first frame (default -- what the boss wants).
// 1.0 = the view ROLLS over as the shader fades in, and rights itself on the
//       way out. That variant only works if "map_thunderstun" is also present in
//       the FADE_SHADERS table in modules/game_shaders/shaders.lua -- u_var0 is
//       what drives the turn, and without that entry it pins at 1.0 and the
//       roll never animates. The two settings must be changed together.
const float ROLL_IN         = 0.0;
const float STAGGER_SPEED   = 2.3;    // how fast the image sways
const float STAGGER_AMOUNT  = 0.020;  // how far it sways, in texture units
const float RIPPLE_AMOUNT   = 0.006;  // per-scanline horizontal ripple
const float ABERRATION      = 0.006;  // red/blue channel separation
const float STRIKE_PERIOD   = 0.85;   // seconds between lightning attempts
const float STRIKE_ODDS     = 0.55;   // fraction of attempts that actually fire
const float TINT_STRENGTH   = 0.35;   // how far colour is pulled to electric blue
const vec3  ARC_COLOR       = vec3(0.75, 0.90, 1.00);

const float PI = 3.14159265;

float hash(float n) { return fract(sin(n) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 57.0;
    return mix(mix(hash(n),        hash(n + 1.0),  f.x),
               mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y);
}

// Strike envelope. Returns (intensity, slot): intensity is 0 for most of the
// time and spikes when a bolt fires; slot seeds the bolt shape so no two
// strikes look alike.
vec2 strike(float t) {
    float slot  = floor(t / STRIKE_PERIOD);
    float phase = fract(t / STRIKE_PERIOD);
    if (hash(slot * 7.13) > STRIKE_ODDS) {
        return vec2(0.0, slot);            // this slot stays quiet
    }
    // Double-tap: hard hit, dip, then a weaker afterflash -- reads as thunder
    // rather than a strobe.
    float hit   = exp(-phase * 22.0);
    float after = exp(-max(phase - 0.16, 0.0) * 14.0) * 0.45;
    return vec2(max(hit, after), slot);
}

// One jagged bolt. The x position is warped by two octaves of noise along y,
// which is what gives it the forked, hand-drawn look.
float bolt(vec2 uv, float seed, float t) {
    float lane = 0.12 + 0.76 * hash(seed * 3.77);
    float x = uv.x - lane;
    x += (noise(vec2(uv.y *  5.0 + seed * 11.0, t * 0.6)) - 0.5) * 0.30;
    x += (noise(vec2(uv.y * 17.0 + seed *  5.0, t * 1.1)) - 0.5) * 0.10;
    float core = smoothstep(0.010, 0.0, abs(x));
    float glow = smoothstep(0.080, 0.0, abs(x)) * 0.30;
    return core + glow;
}

void main() {
    float amt = clamp(u_var0, 0.0, 1.0);

    // ---- 1. roll-over ------------------------------------------------------
    float aspect = max(u_Resolution.x, 1.0) / max(u_Resolution.y, 1.0);
    vec2 c = v_TexCoord - 0.5;
    c.x *= aspect;
    // rollAmt = 1.0 when ROLL_IN is 0 (snap straight to upside down); follows
    // the fade when ROLL_IN is 1 (turn over gradually).
    float rollAmt = mix(1.0, amt, ROLL_IN);
    float ang = PI * ROLL_HALF_TURNS * rollAmt;
    float sa = sin(ang);
    float ca = cos(ang);
    c = vec2(c.x * ca - c.y * sa, c.x * sa + c.y * ca);
    c.x /= aspect;
    vec2 uv = c + 0.5;

    // ---- 2. stagger --------------------------------------------------------
    float t = u_Time * STAGGER_SPEED;
    uv.x += sin(t) * STAGGER_AMOUNT * amt;
    uv.y += cos(t * 0.73) * STAGGER_AMOUNT * 0.7 * amt;
    uv.x += sin(uv.y * 26.0 + t * 1.9) * RIPPLE_AMOUNT * amt;

    // ---- 3. lightning ------------------------------------------------------
    vec2 st = strike(u_Time);
    float flash = st.x * amt;
    uv.x += (hash(st.y * 2.31) - 0.5) * 0.05 * flash;   // the hit kicks the view

    // Sample with chromatic aberration; separation widens during a burst.
    float sep = ABERRATION * amt * (1.0 + flash * 2.5);
    vec4 col;
    col.r = texture2D(u_Tex0, uv + vec2(sep, 0.0)).r;
    col.g = texture2D(u_Tex0, uv).g;
    col.b = texture2D(u_Tex0, uv - vec2(sep, 0.0)).b;
    col.a = texture2D(u_Tex0, uv).a;

    // Whatever the roll pushed past the edge reads as void. Without this the
    // border texels smear into long streaks during the turn.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        col.rgb = vec3(0.0);
    }

    // ---- 4. nerve burn -----------------------------------------------------
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    col.rgb = mix(col.rgb, vec3(lum) * ARC_COLOR, TINT_STRENGTH * amt);

    if (flash > 0.001) {
        float arcs = bolt(uv, st.y, u_Time) + bolt(uv, st.y + 41.0, u_Time) * 0.7;
        col.rgb += ARC_COLOR * arcs * flash * 1.6;
        col.rgb += ARC_COLOR * flash * 0.35;
    }

    gl_FragColor = col * u_Color;
    if (gl_FragColor.a < 0.01) {
        discard;
    }
}
