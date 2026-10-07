uniform sampler2D u_Tex0;          // map framebuffer
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;
uniform float u_var0;              // global fade, 0 = no effect, 1 = full

// ============================================================================
// Cemetery shader — haunted graveyard atmosphere (texture-less)
// ============================================================================
// Intentionally minimal. Four layered effects, all fixed-strength:
//   1. Global desaturation — pulls every pixel toward gray (no mask).
//   2. Cold tint on the whole screen.
//   3. Slight global darkening.
//   4. Dark vignette that closes in at the edges.
// u_var0 scales everything so Lua can fade the shader in/out on enter/exit.

// -------- Desaturation (applied to the entire frame) --------
// 0 = no change, 1 = fully black & white. Lower values keep more of the
// underlying palette visible.
const float DESATURATION     = 0.30;

// -------- Tint (applied to the entire frame) --------
const vec3  TINT_COLOR       = vec3(0.85, 0.86, 0.88);  // cold neutral gray
const float TINT_STRENGTH    = 0.10;

// -------- Global darkening --------
const float DARKEN           = 0.08;  // 0 = unchanged

// -------- Vignette --------
const vec3  VIG_COLOR        = vec3(0.04, 0.04, 0.05);  // near-black gray
const float VIG_INNER        = 0.50;
const float VIG_OUTER        = 1.50;
const float VIG_AMOUNT       = 0.55;

// ============================================================================
// Main
// ============================================================================
void main() {
    vec4 mapColor = texture2D(u_Tex0, v_TexCoord);

    vec2 screenUv = gl_FragCoord.xy / u_Resolution;
    screenUv.y = 1.0 - screenUv.y;

    float fade = clamp(u_var0, 0.0, 1.0);

    // -------- Global desaturation --------
    // Mix each pixel toward its own luminance — that's the classic "pull to
    // gray" operation, uniform across the whole screen.
    vec3 grayed = vec3(dot(mapColor.rgb, vec3(0.299, 0.587, 0.114)));
    vec3 tinted = mix(mapColor.rgb, grayed, DESATURATION * fade);

    // -------- Tint (applied to everything) --------
    tinted = mix(tinted, tinted * TINT_COLOR, TINT_STRENGTH * fade);

    // -------- Global darkening --------
    tinted *= 1.0 - DARKEN * fade;

    // -------- Vignette (dark, not white like the blizzard) --------
    vec2 vigUv = screenUv * 2.0 - 1.0;
    vigUv.x *= u_Resolution.x / u_Resolution.y;
    float vigDist = length(vigUv);
    float vigMask = smoothstep(VIG_INNER, VIG_OUTER, vigDist);
    vigMask = vigMask * vigMask * (3.0 - 2.0 * vigMask);  // smootherstep
    tinted = mix(tinted, VIG_COLOR, vigMask * VIG_AMOUNT * fade);

    gl_FragColor = vec4(tinted, mapColor.a);
}
