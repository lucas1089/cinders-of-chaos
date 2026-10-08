uniform sampler2D u_Tex0;          // map framebuffer
uniform sampler2D u_Tex1;          // nevasca.png (black bg, white snowflakes + streaks)
uniform sampler2D u_Tex2;          // clouds.png (soft tileable noise for wind gusts)
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;
uniform float u_var0;              // global fade amount, 0 = no effect, 1 = full

// ============================================================================
// Storm intensity envelope
// ============================================================================
// The storm runs as a sequence of "segments" of random duration (SEG_MIN..SEG_MAX
// seconds). Each segment targets a random intensity in [0..1]. The current
// intensity smoothly interpolates from the previous segment's target to the
// current segment's target over the segment's duration.
//
// Intensity affects:
//   - how many snowflakes per layer are drawn (via density threshold)
//   - fall speed (stronger storm = faster fall)
//   - wind sway amplitude
//   - color tint and darkening
//   - wind gust opacity
const float SEG_MIN          = 15.0;  // minimum segment duration (seconds)
const float SEG_MAX          = 120.0; // maximum segment duration (seconds)

// DEBUG: set to a value in [0..1] to force a fixed intensity stage and bypass
// the random segment cycle. Set to -1.0 to use the normal dynamic cycle.
//   0.0  = no effect (shader runs but invisible)
//   0.1  = very calm
//   0.3  = light snow
//   0.5  = medium
//   0.8  = strong
//   1.0  = blizzard peak (max whiteout, tightest vignette, densest flakes)
const float FORCE_INTENSITY  = -1.0;

// Hash: float -> [0..1]
float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
// Hash: vec2 -> [0..1]
float h2(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
// Hash: vec2 -> vec2
vec2  h2v(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)),
                          dot(p, vec2(269.5,  183.3)))) * 43758.5453);
}

// Segment duration from segment index.
float segDuration(float i) {
    return mix(SEG_MIN, SEG_MAX, h1(i * 7.13));
}

// Segment target intensity in [0..1].
// Biased to spend most time in calm/medium with occasional strong peaks.
// Low end goes near zero so storms can almost completely die down.
float segTarget(float i) {
    float r = h1(i * 31.7 + 0.5);
    // Remap r via a curve that favors low values but allows occasional peaks.
    // Cube bias -> mostly small values, with a tail reaching 1.0.
    float biased = r * r * r;
    // Ensure we sometimes hit strong blizzards: if r > 0.85, snap to [0.75..1.0]
    if (r > 0.85) {
        biased = mix(0.75, 1.0, (r - 0.85) / 0.15);
    }
    return biased;
}

// Walk segments until we've accumulated enough time to cover u_Time.
// Returns (currentIntensity).
float currentIntensity() {
    // Debug override — bypass the dynamic cycle entirely.
    if (FORCE_INTENSITY >= 0.0) {
        return clamp(FORCE_INTENSITY, 0.0, 1.0);
    }

    // Find current segment and interpolation t within it.
    // This is an unrolled loop with a generous upper bound — in practice
    // segments are 15-120s so 64 iterations cover ~1-8 hours of runtime.
    float t = u_Time;
    float segStart = 0.0;
    float i = 0.0;
    float prevTarget = segTarget(0.0);
    float currTarget = prevTarget;
    float dur = segDuration(0.0);

    for (int k = 0; k < 64; k++) {
        if (t < segStart + dur) break;
        segStart += dur;
        i += 1.0;
        prevTarget = currTarget;
        currTarget = segTarget(i);
        dur = segDuration(i);
    }

    float localT = clamp((t - segStart) / dur, 0.0, 1.0);
    // Smooth (ease) the interpolation between segments.
    float easeT = smoothstep(0.0, 1.0, localT);
    return mix(prevTarget, currTarget, easeT);
}

// ============================================================================
// Snow layers sampled from cosmos.png
// ============================================================================
// Three scrolling layers at different scales and speeds give parallax depth.
// cosmos.png is a black background with small white star-like points — a
// luminance threshold turns it into soft snowflakes.

// UV scale per layer (smaller = larger flakes, more spread out).
const float FAR_SCALE      = 3.5;  // far: many small flakes
const float MID_SCALE      = 2.0;  // mid: medium
const float NEAR_SCALE     = 1.1;  // near: large, sparse

// Fall speed per layer (screen-units per second along fall direction).
const float FAR_SPEED      = 0.018;
const float MID_SPEED      = 0.040;
const float NEAR_SPEED     = 0.075;

// Horizontal drift amplitude per layer.
const float FAR_SWAY       = 0.008;
const float MID_SWAY       = 0.014;
const float NEAR_SWAY      = 0.022;

// Diagonal fall direction (negative Y = downward on screen).
const vec2  FALL_DIR       = vec2(-0.25, -1.0);

// Luminance threshold / softness — controls which pixels of cosmos.png count
// as flakes. Higher threshold = fewer flakes (only the brightest stars).
const float SNOW_THRESHOLD = 0.70;
const float SNOW_SOFTNESS  = 0.20;

// Fade out samples near the texture border so flakes that touch the edge of
// cosmos.png don't appear sliced when fract() wraps the UV.
const float EDGE_FADE      = 0.08;

float sampleSnowLayer(vec2 screenUv, float scale, float speed, float sway,
                      float intensity, float layerSeed, vec2 windOffset) {
    float aspect = u_Resolution.x / u_Resolution.y;
    // Apply wind push BEFORE scaling so the displacement is in screen-space
    // (not multiplied by the layer scale).
    vec2 pushedUv = screenUv + windOffset;
    vec2 uv = vec2(pushedUv.x * aspect, pushedUv.y) * scale;

    // Scroll diagonally; fall speed scales with intensity.
    float fallSpeed = speed * mix(0.6, 1.5, intensity);
    uv += normalize(FALL_DIR) * u_Time * fallSpeed * scale;

    // Horizontal sway.
    uv.x += sin(uv.y * 1.1 + u_Time * 0.6 + layerSeed) * sway * scale * mix(0.4, 1.2, intensity);

    // Offset per layer so they don't sample the same region of the texture.
    uv += vec2(layerSeed * 7.3, layerSeed * 4.1);

    uv = fract(uv);

    // Sample cosmos.png and threshold to extract the bright stars.
    float lum = dot(texture2D(u_Tex1, uv).rgb, vec3(0.299, 0.587, 0.114));
    float mask = smoothstep(SNOW_THRESHOLD, SNOW_THRESHOLD + SNOW_SOFTNESS, lum);

    // Fade out flakes near the texture's seam — stars that bleed across the
    // border of cosmos.png produce visible half-flakes under fract(), so we
    // attenuate samples within EDGE_FADE of any edge.
    float edgeX = min(uv.x, 1.0 - uv.x);
    float edgeY = min(uv.y, 1.0 - uv.y);
    float edge = min(edgeX, edgeY);
    mask *= smoothstep(0.0, EDGE_FADE, edge);

    // Layer density also gated by intensity — at low intensity, fewer flakes
    // survive the threshold bump.
    float intensityGate = mix(0.25, 1.0, intensity);
    return mask * intensityGate;
}

// ============================================================================
// Wind gust system (keeps clouds.png texture, now on u_Tex1)
// ============================================================================
const float GUST_PERIOD          = 10.0;
const float GUST_TRAVEL_TIME     = 5.0;
const float GUST_WIDTH           = 1.6;
const float GUST_HEIGHT          = 1.2;
const float GUST_THRESHOLD       = 0.45;
const float GUST_SOFTNESS        = 0.35;
const float GUST_MAX_OPACITY     = 0.45;
const vec3  GUST_COLOR           = vec3(0.95, 0.97, 1.00);
const float GUST_SKIP_CHANCE     = 0.25;

float gustHash(float i, float salt) {
    return fract(sin(i * 127.1 + salt * 311.7) * 43758.5453);
}

const float W_LEFT_RIGHT = 3.0;
const float W_RIGHT_LEFT = 2.0;
const float W_TOP_BOTTOM = 1.0;
const float W_BOTTOM_TOP = 0.5;
const float W_DIAG_TL_BR = 1.5;
const float W_DIAG_TR_BL = 1.5;

int pickVariation(float r) {
    float total = W_LEFT_RIGHT + W_RIGHT_LEFT + W_TOP_BOTTOM + W_BOTTOM_TOP + W_DIAG_TL_BR + W_DIAG_TR_BL;
    float t = r * total;
    if (t < W_LEFT_RIGHT) return 0;
    t -= W_LEFT_RIGHT;
    if (t < W_RIGHT_LEFT) return 1;
    t -= W_RIGHT_LEFT;
    if (t < W_TOP_BOTTOM) return 2;
    t -= W_TOP_BOTTOM;
    if (t < W_BOTTOM_TOP) return 3;
    t -= W_BOTTOM_TOP;
    if (t < W_DIAG_TL_BR) return 4;
    return 5;
}

vec2 variationCenter(int variation, float progress) {
    float halfW = GUST_WIDTH  * 0.5;
    float halfH = GUST_HEIGHT * 0.5;
    if (variation == 0) return vec2(mix(-halfW, 1.0 + halfW, progress), 0.5);
    if (variation == 1) return vec2(mix(1.0 + halfW, -halfW, progress), 0.5);
    if (variation == 2) return vec2(0.5, mix(-halfH, 1.0 + halfH, progress));
    if (variation == 3) return vec2(0.5, mix(1.0 + halfH, -halfH, progress));
    if (variation == 4) return vec2(mix(-halfW, 1.0 + halfW, progress),
                                    mix(-halfH, 1.0 + halfH, progress));
    return vec2(mix(1.0 + halfW, -halfW, progress),
                mix(-halfH, 1.0 + halfH, progress));
}

// Unit direction vector of the gust's movement, per variation.
vec2 variationDirection(int variation) {
    if (variation == 0) return vec2( 1.0,  0.0);  // L -> R
    if (variation == 1) return vec2(-1.0,  0.0);  // R -> L
    if (variation == 2) return vec2( 0.0,  1.0);  // T -> B
    if (variation == 3) return vec2( 0.0, -1.0);  // B -> T
    if (variation == 4) return normalize(vec2( 1.0,  1.0));  // TL -> BR
    return normalize(vec2(-1.0,  1.0));                      // TR -> BL
}

// ============================================================================
// Adaptive map blur — simulates reduced visibility during heavy snow
// ============================================================================
// A cheap 5-tap (plus the center) box blur whose sample offset scales with
// intensity. At calm intensity the offset is zero, so neighboring samples
// all collapse to the center and the result is identical to a single
// texture2D — effectively free. At blizzard intensity, offsets spread out
// and the map becomes visibly blurred/hazy.
vec4 sampleMap(vec2 uv, float intensity) {
    // Blur kicks in gradually after a threshold so calm/medium weather stays
    // sharp. Max offset ~1.8 pixels at full blizzard.
    float blurAmount = smoothstep(0.35, 1.0, intensity);
    if (blurAmount <= 0.0) {
        return texture2D(u_Tex0, uv);
    }

    float px = 1.8 * blurAmount / u_Resolution.x;
    float py = 1.8 * blurAmount / u_Resolution.y;

    vec4 c = texture2D(u_Tex0, uv) * 0.36;
    c += texture2D(u_Tex0, uv + vec2( px,  0.0)) * 0.16;
    c += texture2D(u_Tex0, uv + vec2(-px,  0.0)) * 0.16;
    c += texture2D(u_Tex0, uv + vec2(0.0,  py)) * 0.16;
    c += texture2D(u_Tex0, uv + vec2(0.0, -py)) * 0.16;
    return c;
}

// ============================================================================
// Main
// ============================================================================
void main() {
    float intensity = currentIntensity();
    vec4 mapColor = sampleMap(v_TexCoord, intensity);
    float mapLum = dot(mapColor.rgb, vec3(0.299, 0.587, 0.114));

    // Screen-space UV anchored to the viewport (not to the map / world).
    vec2 screenUv = gl_FragCoord.xy / u_Resolution;
    screenUv.y = 1.0 - screenUv.y;

    // -------- Wind gust pre-pass (compute gust state for wind push) --------
    // We compute the active gust BEFORE sampling snow so we can use the
    // gust's direction + proximity to push the snow flakes around — making
    // the wind feel like it's actually shoving the particles.
    float gustMask = 0.0;
    vec2  windPush = vec2(0.0);
    float gustIndex = floor(u_Time / GUST_PERIOD);
    float phase = mod(u_Time, GUST_PERIOD);

    // Per-gust travel time — intensity pushes toward shorter (faster) gusts.
    float travelBase = mix(1.15, 0.65, intensity);
    float travelTime = GUST_TRAVEL_TIME * travelBase * mix(0.85, 1.15, gustHash(gustIndex, 7.0));

    // Dynamic skip chance: even calm weather gets plenty of gusts now.
    float dynamicSkip = mix(0.30, 0.0, smoothstep(0.1, 0.95, intensity));
    float skipRoll = gustHash(gustIndex, 91.0);
    bool active = (skipRoll >= dynamicSkip) && (phase <= travelTime);

    // We capture these for both the wind push and the visual gust render.
    int   variation   = 0;
    vec2  gustCenter  = vec2(0.5);
    vec2  gustDir     = vec2(1.0, 0.0);
    float progress    = 0.0;
    float windInfluence = 0.0;  // 0..1, how strongly this pixel is in the gust

    if (active) {
        progress   = phase / travelTime;
        variation  = pickVariation(gustHash(gustIndex, 13.0));
        gustCenter = variationCenter(variation, progress);
        gustDir    = variationDirection(variation);

        // Aspect-corrected vector from gust center to this pixel.
        float aspect = u_Resolution.x / u_Resolution.y;
        vec2  toPixel = vec2((screenUv.x - gustCenter.x) * aspect,
                              screenUv.y - gustCenter.y);

        // Project the pixel offset onto the gust's direction. Pixels in the
        // *wake* of the gust (behind it relative to its motion) are still
        // being dragged along — so we count both the radial proximity and the
        // tangential extent. This avoids the harsh "snap when in radius" feel.
        float along  = dot(toPixel, gustDir);          // signed distance along motion
        vec2  tangent = toPixel - gustDir * along;
        float across = length(tangent);                // perpendicular distance

        // Wider, softer influence: across must be small (close to the line
        // the gust is sweeping along), but along can be either ahead or
        // behind by some amount.
        float acrossMask = 1.0 - smoothstep(0.25, 0.75, across);
        // Asymmetric along mask: pixels behind the gust (negative along) get
        // a longer drag tail than pixels ahead (which haven't been hit yet).
        float aheadMask  = 1.0 - smoothstep(0.0, 0.35, max(along, 0.0));
        float behindMask = 1.0 - smoothstep(0.0, 0.85, max(-along, 0.0));
        float alongMask  = max(aheadMask, behindMask);

        windInfluence = acrossMask * alongMask;

        // Smooth temporal ramp — slow build-up at the start of the sweep,
        // sustain, then a gentle release. This gives the "flow" feel instead
        // of a symmetric pop in / pop out.
        float windEnvelope = smoothstep(0.0, 0.35, progress)
                           * (1.0 - smoothstep(0.70, 1.0, progress));
        windInfluence *= windEnvelope;

        // Base push magnitude — much gentler than before so the flow looks
        // like drift, not teleportation.
        const float BASE_PUSH = 0.05;
        float pushScale = mix(0.5, 1.4, intensity);
        windPush = gustDir * (BASE_PUSH * pushScale * windInfluence);

        // Snow must never drift *upward*. The gust system has bottom->top and
        // upward-diagonal variations whose gustDir has a negative screen-Y
        // component; pushing the snow UV along that makes flakes visibly rise,
        // which looks wrong (snow doesn't fall up). screenUv.y grows downward
        // (it was flipped above), so an upward push is windPush.y < 0. Clamp
        // the vertical component to >= 0 so the wind can still shove flakes
        // sideways during any gust, but it can only ever nudge them down or
        // leave the natural fall untouched — never lift them.
        windPush.y = max(windPush.y, 0.0);
    }

    // -------- Snow: 3 layers sampled from cosmos.png --------
    // Per-layer wind weighting — near layer reacts most to wind (parallax),
    // far layer barely budges.
    float farSnow  = sampleSnowLayer(screenUv, FAR_SCALE,  FAR_SPEED,  FAR_SWAY,
                                     intensity, 1.0, windPush * 0.25);
    float midSnow  = sampleSnowLayer(screenUv, MID_SCALE,  MID_SPEED,  MID_SWAY,
                                     intensity, 2.0, windPush * 0.60);
    float nearSnow = sampleSnowLayer(screenUv, NEAR_SCALE, NEAR_SPEED, NEAR_SWAY,
                                     intensity, 3.0, windPush * 1.00);

    // Split snow into "distant" (far + mid) and "near" layers.
    float distantSnowMask = clamp(farSnow * 0.45 + midSnow * 0.75, 0.0, 1.0);
    float nearSnowMask    = clamp(nearSnow * 1.0, 0.0, 1.0);

    // -------- Wind gust visual render --------
    if (active) {
        vec2 local;
        local.x = (screenUv.x - (gustCenter.x - GUST_WIDTH  * 0.5)) / GUST_WIDTH;
        local.y = (screenUv.y - (gustCenter.y - GUST_HEIGHT * 0.5)) / GUST_HEIGHT;

        if (local.x >= 0.0 && local.x <= 1.0 && local.y >= 0.0 && local.y <= 1.0) {
            float gustLum = dot(texture2D(u_Tex2, local).rgb, vec3(0.299, 0.587, 0.114));
            float gustShape = smoothstep(GUST_THRESHOLD, GUST_THRESHOLD + GUST_SOFTNESS, gustLum);

            // Elliptical soft mask — rounds off the cloud texture's edges.
            vec2 centered = local * 2.0 - 1.0;
            float dist = length(centered);
            float shapeMask = 1.0 - smoothstep(0.55, 1.0, dist);

            float edgeFade = smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.85, 1.0, progress));

            // Gusts stay visible even in calm weather — only the peak
            // intensity gets a noticeable boost.
            float gustScale = mix(0.70, 1.0, intensity);

            gustMask = gustShape * shapeMask * edgeFade * GUST_MAX_OPACITY * gustScale;
        }
    }

    // -------- Global fade (u_var0) --------
    // Scale all storm effects by u_var0 so Lua can fade the shader in/out
    // smoothly instead of abruptly enabling/disabling it.
    float fade = clamp(u_var0, 0.0, 1.0);
    distantSnowMask *= fade;
    nearSnowMask    *= fade;
    gustMask        *= fade;

    // -------- Color grading --------
    // Winter tint and darkening scale with intensity AND global fade.
    //
    // Important: apply the cold tint only to shadow/ambient pixels, not to
    // bright highlights. Otherwise warm light sources (torches, fires) get
    // their red/green channels crushed and look sickly green. We use the
    // pixel's luminance as a mask — only darker areas get the blue bias.
    vec3  TINT_COLOR     = vec3(0.85, 0.92, 1.00);
    float tintStrength   = mix(0.03, 0.14, intensity) * fade;
    float darkenAmount   = mix(0.0, 0.18, intensity) * fade; // 0 = no change
    float darken         = 1.0 - darkenAmount;

    // Luminance mask: 1.0 for dark pixels, 0.0 for bright highlights.
    // Highlights (> ~0.7 lum) keep their original color.
    float lumMask = 1.0 - smoothstep(0.35, 0.75, mapLum);
    float maskedTintStrength = tintStrength * lumMask;

    vec3 tinted = mix(mapColor.rgb, mapColor.rgb * TINT_COLOR, maskedTintStrength);
    tinted *= darken;

    // -------- Whiteout (global fog) --------
    // Partially mask by luminance too — highlights (torches, fires) should
    // still cut through the fog so the player can see light sources.
    vec3  WHITEOUT_COLOR     = vec3(0.90, 0.94, 1.00);
    float whiteoutBase       = smoothstep(0.20, 1.0, intensity) * 0.42 * fade;
    float whiteoutStrength   = whiteoutBase * mix(0.4, 1.0, lumMask);
    tinted = mix(tinted, WHITEOUT_COLOR, whiteoutStrength);

    // -------- White vignette (blizzard "closes in") --------
    // Aggressive vignette — edges go almost fully white during peak blizzard,
    // only the immediate surroundings of the player stay readable.
    vec2 vigUv = screenUv * 2.0 - 1.0;
    vigUv.x *= u_Resolution.x / u_Resolution.y;
    float vigDist = length(vigUv);
    // Inner radius tightens with intensity — blizzards close in on the player.
    // Widened inner/outer gap so the transition between the clear "eye" and
    // the whiteout fades gradually instead of showing a visible ring.
    float vigInner = mix(0.40, 0.10, intensity);
    float vigOuter = mix(1.60, 1.20, intensity);
    float vigMask = smoothstep(vigInner, vigOuter, vigDist);
    // Extra easing (smootherstep-style) to soften the curve further.
    vigMask = vigMask * vigMask * (3.0 - 2.0 * vigMask);
    float vigAmount = vigMask * smoothstep(0.10, 0.90, intensity) * 0.80 * fade;
    tinted = mix(tinted, WHITEOUT_COLOR, vigAmount);

    // -------- Compose (screen blend) --------
    // Layering order (bottom to top):
    //   1. tinted map (already has tint + whiteout + vignette applied)
    //   2. distant snow (far + mid)  — then whiteout again to make it fade
    //      into the fog
    //   3. gusts
    //   4. drift streaks
    //   5. near snow (crisp, on top of the fog — closest to the "camera")
    vec3 snowColor = vec3(0.96, 0.98, 1.00);

    // Step 1: distant snow on top of the already-fogged map.
    vec3 distantSnowRGB = snowColor * distantSnowMask;
    vec3 withDistantSnow = 1.0 - (1.0 - tinted) * (1.0 - distantSnowRGB);

    // Step 2: re-apply part of the whiteout over the distant snow so the
    // flakes far away get swallowed by the fog, not painted on top of it.
    withDistantSnow = mix(withDistantSnow, WHITEOUT_COLOR,
                          whiteoutStrength * 0.65);

    // Step 3: gusts.
    vec3 gustLayer = GUST_COLOR * gustMask;
    vec3 withGust = 1.0 - (1.0 - withDistantSnow) * (1.0 - gustLayer);

    // Step 4: near snow — crisp, untouched by fog.
    vec3 nearSnowRGB = snowColor * nearSnowMask;
    vec3 finalRGB = 1.0 - (1.0 - withGust) * (1.0 - nearSnowRGB);

    gl_FragColor = vec4(finalRGB, mapColor.a);
}
