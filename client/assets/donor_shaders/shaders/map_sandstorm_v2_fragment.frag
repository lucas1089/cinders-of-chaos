uniform sampler2D u_Tex0;          // map framebuffer
uniform sampler2D u_Tex1;          // clouds.png (soft tileable noise for dust gusts)
                                   // NOTE: sand grains are 100% procedural now (no grain texture)
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;
uniform float u_var0;              // global fade amount, 0 = no effect, 1 = full

// Shared cycle time (seconds). Set by the client from a per-ZONE clock the
// server broadcasts so every player in the same sandstorm zone/instance sees the
// EXACT SAME intensity phase (calm/storm), instead of each client running its
// own local-since-boot u_Time. Defaults to 0 (the GL value for an unset uniform);
// the client also pushes -1 when there is no zone. When <= 0 the cycle falls back
// to u_Time so a manually-applied shader (no zone) still animates. Only the
// intensity ENVELOPE reads this; grains/gusts/haze keep using u_Time so their
// motion stays smooth and per-client, never snapping when zoneTime re-anchors.
uniform float u_zoneTime;

// ============================================================================
// Sandstorm intensity envelope
// ============================================================================
// The storm runs as a sequence of "segments" of random duration (SEG_MIN..SEG_MAX
// seconds). Each segment targets a random intensity. The current intensity
// smoothly interpolates from the previous segment's target to the current one.
//
// Like the blizzard, the sandstorm now has REAL calm windows: most of the time
// the air is dead quiet — no airborne sand, no dust gusts, no yellow tint, only
// faint heat-haze shimmer over the dunes — and only occasionally does it
// escalate into a strong, blowing sandstorm. The intensity curve is biased
// toward the low end so calm dominates and big storms feel like an event.
//
// Intensity affects:
//   - how many grains per layer are drawn (via density threshold)
//   - blow speed (stronger storm = faster horizontal sweep)
//   - vertical bob amplitude
//   - yellow tint and darkening
//   - dust gust opacity
const float SEG_MIN          = 18.0;  // minimum segment duration (seconds)
const float SEG_MAX          = 110.0; // maximum segment duration (seconds)

// DEBUG: set to a value in [0..1] to force a fixed intensity stage and bypass
// the random segment cycle. Set to -1.0 to use the normal dynamic cycle.
//   0.0  = DEAD CALM — no sand at all, only faint heat-haze shimmer
//   0.05 = right at the calm threshold (sand just begins to appear)
//   0.3  = light sand (typical "weak" blow)
//   0.5  = normal blowing sand
//   0.8  = strong
//   1.0  = sandstorm peak (max haze, tightest vignette, densest grains)
const float FORCE_INTENSITY  = -1.0;

// Hash: float -> [0..1]
float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
// Hash: vec2 -> [0..1]
float h2(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
// Hash: vec2 -> vec2 (used to place a grain at a random spot inside a cell)
vec2  h2v(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)),
                          dot(p, vec2(269.5,  183.3)))) * 43758.5453);
}

// Segment duration from segment index.
float segDuration(float i) {
    return mix(SEG_MIN, SEG_MAX, h1(i * 7.13));
}

// Segment target intensity in [0..1].
// Biased HARD toward the low end so the desert spends most of its time fully
// calm (intensity ~0 -> only heat-haze, no sand). A cube curve crushes most
// rolls down near zero; only the rare high roll escalates into a real storm.
// There is intentionally NO floor — calm means calm.
float segTarget(float i) {
    float r = h1(i * 31.7 + 0.5);
    // Low rolls -> cube curve crushes them toward 0 (dead calm dominates).
    // High-but-not-peak rolls relax toward a quadratic so there's still room
    // for the occasional light/medium blow between the calms and the peaks.
    float biased = mix(r * r * r, r * r, smoothstep(0.5, 0.88, r));
    // Rare extreme sandstorm: top ~12% of rolls snap up to [0.78 .. 1.0].
    if (r > 0.88) {
        biased = mix(0.78, 1.0, (r - 0.88) / 0.12);
    }
    return biased;
}

// Walk segments until we've accumulated enough time to cover u_Time.
float currentIntensity() {
    if (FORCE_INTENSITY >= 0.0) {
        return clamp(FORCE_INTENSITY, 0.0, 1.0);
    }

    // Drive the intensity envelope from the shared per-zone clock when the
    // client provided one (u_zoneTime > 0); otherwise fall back to the local
    // u_Time so a manually-applied (zone-less) sandstorm still cycles. The
    // `> 0` test (not `>= 0`) also covers the GL default of 0 for an unset
    // uniform, so a shader applied outside the zone opcode never freezes at t=0.
    float t = (u_zoneTime > 0.0) ? u_zoneTime : u_Time;
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
    float easeT = smoothstep(0.0, 1.0, localT);
    return mix(prevTarget, currTarget, easeT);
}

// ============================================================================
// Storm activity gate
// ============================================================================
// Below CALM_THRESHOLD the desert is considered fully calm: ALL sand effects
// (grains, dust gusts, yellow tint, haze, vignette) are switched off so the
// only thing left on screen is the faint heat-haze shimmer. The gate ramps
// smoothly from 0 -> 1 across [CALM_THRESHOLD .. CALM_THRESHOLD + CALM_RAMP]
// so the storm fades in instead of popping. Multiply any sand-only term by
// this gate to make it vanish during calm windows.
const float CALM_THRESHOLD = 0.06;  // intensity below this = dead calm (no sand)
const float CALM_RAMP      = 0.10;  // width of the fade-in band above the floor

float stormActivity(float intensity) {
    return smoothstep(CALM_THRESHOLD, CALM_THRESHOLD + CALM_RAMP, intensity);
}

// ============================================================================
// Procedural sand grain layers (NO texture)
// ============================================================================
// Three scrolling layers at different scales and speeds give parallax depth.
// Each layer lays an invisible grid over the screen; every cell may hold one
// round grain at a hashed sub-cell position. Small grains = isolated specks
// that read as wind-blown sand, never as a regular grid.
//
// Sand is wind-driven: motion is 100% HORIZONTAL. Each horizontal lane scrolls
// at its own speed, so grains travel at different rates and arrive at different
// times instead of moving as one rigid sheet.
//
// Grain SIZE is constant in SCREEN space (see GRAIN_RS), so every grain looks
// the same size regardless of its layer's grid density. The grid `scale` only
// controls how MANY grains and how far apart — not how big.

// Grid density per layer (larger = more, more spread-out grains). Size is NOT
// affected by these (see GRAIN_RS); only count/spacing and parallax speed are.
const float FAR_SCALE      = 34.0;
const float MID_SCALE      = 22.0;
const float NEAR_SCALE     = 13.0;

// Blow speed per layer, in screen-fractions/sec. Cranked WAY up — this is a
// raging sandstorm, so the sand whips violently across the screen. The near
// layer nearly crosses the whole viewport every second.
const float FAR_SPEED      = 0.55;
const float MID_SPEED      = 0.85;
const float NEAR_SPEED     = 1.30;

// Blow direction: 100% horizontal, to the left.
const vec2  BLOW_DIR       = vec2(-1.0, 0.0);

// Grain size in SCREEN fraction of height (≈ GRAIN_RS * screen_height pixels).
// Constant across layers so all grains are identical in size. Inset by the
// radius so a grain never crosses its cell boundary (no half-clipped grains).
const float GRAIN_RS       = 0.0010;
const float GRAIN_SOFT_RS  = 0.0007;

float sampleSandLayer(vec2 screenUv, float scale, float speed,
                      float intensity, float layerSeed, vec2 windOffset) {
    float aspect = u_Resolution.x / u_Resolution.y;
    // Apply wind push BEFORE scaling so the displacement is in screen-space.
    vec2 pushedUv = screenUv + windOffset;
    vec2 uv = vec2(pushedUv.x * aspect, pushedUv.y) * scale;

    // Per-layer offset so layers don't share the same grid cells.
    uv += vec2(layerSeed * 7.3, layerSeed * 4.1);

    // Constant blow speed — NOT tied to intensity. The sand always streams at
    // the same rate, so when a storm fades out the grains keep moving at full
    // speed and simply fade away (via the activity/fade masks in main()) rather
    // than visibly decelerating to a crawl before disappearing.
    float blowSpeed = speed;
    vec2  dir = normalize(BLOW_DIR);   // on-screen travel direction

    // Every grain in this layer blows at the SAME speed (no per-lane speed
    // jitter) so nothing ever looks like it's slowing down or speeding up —
    // the whole sheet streams uniformly. Each horizontal lane still gets a
    // constant start-phase offset so the lanes don't line up into a visible
    // grid, but that offset never changes the travel rate.
    float lane      = floor(uv.y);
    float lanePhase = h1(lane * 3.7 + layerSeed * 5.9) * 100.0;

    // Scroll so grains TRAVEL along `dir` (subtracting the offset moves the
    // pattern toward +dir on screen). dir is horizontal, so motion is too.
    uv -= dir * u_Time * blowSpeed * scale;
    uv.x += lanePhase;                 // constant per-lane offset to decorrelate

    // -------- Procedural grain clusters (constant on-screen size) --------
    // Radius/softness are converted from screen fraction into this layer's cell
    // units (× scale), so the rendered disc is the same pixel size everywhere.
    float rCell = GRAIN_RS      * scale;
    float sCell = GRAIN_SOFT_RS * scale;
    vec2 cell = floor(uv);
    vec2 f    = fract(uv);

    // Per-cell existence roll — only some cells spawn a cluster, and the share
    // that do grows with intensity (denser storm = more airborne sand).
    float roll    = h2(cell * 1.7 + vec2(layerSeed * 3.1, layerSeed * 5.7));
    float density = mix(0.18, 0.80, intensity);
    float exists  = smoothstep(1.0 - density - 0.04, 1.0 - density + 0.04, roll);

    // Cluster size: each spawning cell holds a RANDOM number of grains packed
    // close together — sometimes a lone speck, sometimes a tight group of a
    // few. Roll an integer count in [1 .. CLUSTER_MAX] per cell.
    const int   CLUSTER_MAX = 5;
    float countRoll = h2(cell * 2.3 + vec2(layerSeed * 9.7, layerSeed * 4.3));
    int   grainCount = 1 + int(floor(countRoll * float(CLUSTER_MAX)));  // 1..5

    // Spacing must look ORGANIC, not gridded. Three layers of randomness:
    //   1. Per-CELL spread — each clump picks its own overall tightness, so
    //      some groups are packed and others looser. Never a fixed span.
    //   2. Per-GRAIN polar offset — every grain sits at its own random angle
    //      AND its own random distance from the anchor, so even within one
    //      clump the gaps between grains are all different.
    //   3. Free anchor — the cluster anchor roams the WHOLE cell (not pinned
    //      near the center). Combined with toroidal distance below, clusters in
    //      neighbouring cells can land right next to each other or far apart,
    //      so the gaps BETWEEN clusters vary just as much as within them.
    const float MAX_SPAN = 0.45;  // largest a clump can ever spread (cell units)
    float spreadRoll = h2(cell * 5.1 + vec2(layerSeed * 2.7, layerSeed * 8.9));
    float cellSpread = mix(0.03, MAX_SPAN, spreadRoll * spreadRoll);  // bias tight

    // Anchor anywhere in the cell — no inset. Grain clipping at the boundary is
    // avoided by measuring distance toroidally (wrapping across cell edges)
    // instead of insetting the anchor, which would re-regularize the spacing.
    vec2  anchor = h2v(cell + layerSeed);

    float grain = 0.0;
    for (int gi = 0; gi < CLUSTER_MAX; gi++) {
        if (gi >= grainCount) break;
        // Each grain: an independent random angle and random radius around the
        // anchor (polar scatter). sqrt(radiusRoll) keeps the distribution even
        // across the disc instead of clumping at the center.
        float gf      = float(gi);
        float angRoll = h1(dot(cell, vec2(12.99, 78.23)) + gf * 3.17 + layerSeed * 1.9);
        float radRoll = h1(dot(cell, vec2(39.71, 11.45)) + gf * 7.51 + layerSeed * 4.6);
        float ang     = angRoll * 6.2831853;
        float rad     = sqrt(radRoll) * cellSpread;
        vec2  gpos    = anchor + vec2(cos(ang), sin(ang)) * rad;
        // Toroidal distance: wrap the delta into [-0.5, 0.5] on each axis so a
        // grain near one edge is correctly close to the neighbouring cell's
        // fragments — no half-clipped discs, no inset needed.
        vec2  delta   = fract(f - gpos + 0.5) - 0.5;
        float d       = length(delta);
        grain         = max(grain, smoothstep(rCell, rCell - sCell, d));
    }

    return grain * exists;
}

// ============================================================================
// Dust gust system (yellow clouds sweeping across, from clouds.png on u_Tex1)
// ============================================================================
const float GUST_PERIOD          = 9.0;
const float GUST_TRAVEL_TIME     = 5.0;
const float GUST_WIDTH           = 1.8;
const float GUST_HEIGHT          = 1.2;
const float GUST_THRESHOLD       = 0.42;
const float GUST_SOFTNESS        = 0.38;
const float GUST_MAX_OPACITY     = 0.50;
const vec3  GUST_COLOR           = vec3(0.86, 0.72, 0.42);   // yellow-sand dust
const float GUST_SKIP_CHANCE     = 0.20;

float gustHash(float i, float salt) {
    return fract(sin(i * 127.1 + salt * 311.7) * 43758.5453);
}

// Heavily weight horizontal sweeps — a sandstorm blows sideways, not up/down.
const float W_LEFT_RIGHT = 1.0;
const float W_RIGHT_LEFT = 4.0;   // dominant: matches BLOW_DIR (to the left)
const float W_TOP_BOTTOM = 0.4;
const float W_BOTTOM_TOP = 0.2;
const float W_DIAG_TL_BR = 1.2;
const float W_DIAG_TR_BL = 1.6;

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

vec2 variationDirection(int variation) {
    if (variation == 0) return vec2( 1.0,  0.0);  // L -> R
    if (variation == 1) return vec2(-1.0,  0.0);  // R -> L
    if (variation == 2) return vec2( 0.0,  1.0);  // T -> B
    if (variation == 3) return vec2( 0.0, -1.0);  // B -> T
    if (variation == 4) return normalize(vec2( 1.0,  1.0));  // TL -> BR
    return normalize(vec2(-1.0,  1.0));                      // TR -> BL
}

// ============================================================================
// Heat-haze shimmer — wobbles the map sampling UV like hot air over the dunes
// ============================================================================
// Subtle slow hot-air shimmer (low amplitude + low frequencies), not a nervous
// per-pixel jitter.
//
// AMPLITUDE NOTE: this offsets the UV used to sample the low-res map
// framebuffer. With Antialiasing OFF the framebuffer is NEAREST-filtered, so
// even a sub-texel offset makes pixels visibly snap across texel boundaries and
// the wobble looks strong. With Antialiasing ON it's LINEAR-filtered, so a
// sub-texel offset just smoothly blends and is nearly invisible. The amplitude
// below is therefore sized so the shimmer is still perceptible under LINEAR
// (AA on) — roughly ~1-2 framebuffer texels — while staying gentle under
// NEAREST. Don't drop it back near ~0.0003 or it vanishes with AA on.
// Multiplied by fade so it eases in/out with the shader.
//
// The shimmer belongs to the CALM desert, not the storm: it's strongest when
// there's no sand and fades out as the sandstorm builds, so a strong storm
// shows blowing sand only (no heat-haze). calmFactor: 1 below ~0.3 intensity,
// ramping down to 0 by ~0.7.
vec2 heatHaze(vec2 uv, float intensity, float fade) {
    float calmFactor = 1.0 - smoothstep(0.30, 0.70, intensity);
    float amp = 0.0014 * calmFactor * fade;
    float wx = sin(uv.y * 12.0 + u_Time * 1.2) * amp
             + sin(uv.y * 6.0  - u_Time * 0.7) * amp * 0.5;
    float wy = sin(uv.x * 9.0  + u_Time * 0.9) * amp * 0.6;
    return vec2(wx, wy);
}

// ============================================================================
// Adaptive map blur — simulates reduced visibility during heavy sand
// ============================================================================
vec4 sampleMap(vec2 uv, float intensity) {
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
    float fade = clamp(u_var0, 0.0, 1.0);

    // Activity gate: 0 during calm windows, 1 once a real storm builds up.
    // Everything sand-related (grains, gusts, tint, haze, vignette) is scaled
    // by this so calm = only heat-haze. Heat-haze itself is intentionally NOT
    // gated — the dunes always shimmer a little, even in dead calm.
    float activity = stormActivity(intensity);

    // Heat-haze: wobble the map UV before sampling so the scene shimmers.
    // Driven by raw intensity (not the gate) so the calm desert still ripples.
    //
    // Edge-only mask: the shimmer is confined to the screen EDGES/CORNERS. The
    // center stays a clean, undistorted circle (like the vignette's clear eye).
    // Radial distance from center: 0 at center, ~1 toward the edges. The map
    // texCoord (v_TexCoord) spans the viewport, so center it and aspect-correct.
    vec2  hazeUv   = (v_TexCoord * 2.0 - 1.0);
    hazeUv.x      *= u_Resolution.x / u_Resolution.y;
    float hazeDist = length(hazeUv);
    // 0 inside HAZE_INNER (clean circle), ramping to 1 by HAZE_OUTER (edges).
    const float HAZE_INNER = 0.55;
    const float HAZE_OUTER = 1.15;
    float edgeMask = smoothstep(HAZE_INNER, HAZE_OUTER, hazeDist);

    vec2 mapUv = v_TexCoord + heatHaze(v_TexCoord, intensity, fade) * edgeMask;
    vec4 mapColor = sampleMap(mapUv, intensity);
    float mapLum = dot(mapColor.rgb, vec3(0.299, 0.587, 0.114));

    // Screen-space UV anchored to the viewport (not to the map / world).
    vec2 screenUv = gl_FragCoord.xy / u_Resolution;
    screenUv.y = 1.0 - screenUv.y;

    // -------- Dust gust pre-pass (compute gust state for wind push) --------
    float gustMask = 0.0;
    vec2  windPush = vec2(0.0);
    float gustIndex = floor(u_Time / GUST_PERIOD);
    float phase = mod(u_Time, GUST_PERIOD);

    float travelBase = mix(1.10, 0.55, intensity);   // stronger storm = faster gusts
    float travelTime = GUST_TRAVEL_TIME * travelBase * mix(0.85, 1.15, gustHash(gustIndex, 7.0));

    // Weak storms get fewer dust sweeps; during dead calm there are NONE
    // (the activity gate below forces them off entirely).
    float dynamicSkip = mix(0.55, 0.0, smoothstep(0.1, 0.9, intensity));
    float skipRoll = gustHash(gustIndex, 91.0);
    bool active = (activity > 0.0) && (skipRoll >= dynamicSkip) && (phase <= travelTime);

    int   variation   = 0;
    vec2  gustCenter  = vec2(0.5);
    vec2  gustDir     = vec2(1.0, 0.0);
    float progress    = 0.0;
    float windInfluence = 0.0;

    if (active) {
        progress   = phase / travelTime;
        variation  = 1;  // force right->left so the dust cloud blows the SAME way as the grains
        gustCenter = variationCenter(variation, progress);
        gustDir    = variationDirection(variation);

        float aspect = u_Resolution.x / u_Resolution.y;
        vec2  toPixel = vec2((screenUv.x - gustCenter.x) * aspect,
                              screenUv.y - gustCenter.y);

        float along  = dot(toPixel, gustDir);
        vec2  tangent = toPixel - gustDir * along;
        float across = length(tangent);

        float acrossMask = 1.0 - smoothstep(0.25, 0.80, across);
        float aheadMask  = 1.0 - smoothstep(0.0, 0.35, max(along, 0.0));
        float behindMask = 1.0 - smoothstep(0.0, 0.90, max(-along, 0.0));
        float alongMask  = max(aheadMask, behindMask);

        windInfluence = acrossMask * alongMask;

        float windEnvelope = smoothstep(0.0, 0.35, progress)
                           * (1.0 - smoothstep(0.70, 1.0, progress));
        windInfluence *= windEnvelope;

        // Gust push is a SUBTLE nudge, not a drag. Because windPush displaces
        // the grain UV by an amount that rises and falls with the gust
        // envelope, a large value makes the sand visibly shoot forward as the
        // gust builds and then snap BACK as it releases — reading as "fast one
        // way, then slows and reverses". Keep it tiny so the grains just waver
        // slightly under a passing gust while still streaming the same way.
        const float BASE_PUSH = 0.012;
        windPush = gustDir * (BASE_PUSH * windInfluence);

        // Grains must never drift upward. screenUv.y grows downward (flipped
        // above), so an upward push is windPush.y < 0 — clamp it out.
        windPush.y = max(windPush.y, 0.0);
    }

    // -------- Sand grains: 3 parallax layers --------
    float farSand  = sampleSandLayer(screenUv, FAR_SCALE,  FAR_SPEED,
                                     intensity, 1.0, windPush * 0.25);
    float midSand  = sampleSandLayer(screenUv, MID_SCALE,  MID_SPEED,
                                     intensity, 2.0, windPush * 0.60);
    float nearSand = sampleSandLayer(screenUv, NEAR_SCALE, NEAR_SPEED,
                                     intensity, 3.0, windPush * 1.00);

    float distantSandMask = clamp(farSand * 0.50 + midSand * 0.80, 0.0, 1.0);
    float nearSandMask    = clamp(nearSand * 1.0, 0.0, 1.0);

    // -------- Dust gust visual render --------
    if (active) {
        vec2 local;
        local.x = (screenUv.x - (gustCenter.x - GUST_WIDTH  * 0.5)) / GUST_WIDTH;
        local.y = (screenUv.y - (gustCenter.y - GUST_HEIGHT * 0.5)) / GUST_HEIGHT;

        if (local.x >= 0.0 && local.x <= 1.0 && local.y >= 0.0 && local.y <= 1.0) {
            float gustLum = dot(texture2D(u_Tex1, local).rgb, vec3(0.299, 0.587, 0.114));
            float gustShape = smoothstep(GUST_THRESHOLD, GUST_THRESHOLD + GUST_SOFTNESS, gustLum);

            vec2 centered = local * 2.0 - 1.0;
            float dist = length(centered);
            float shapeMask = 1.0 - smoothstep(0.55, 1.0, dist);

            float edgeFade = smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.85, 1.0, progress));

            float gustScale = mix(0.75, 1.0, intensity);

            gustMask = gustShape * shapeMask * edgeFade * GUST_MAX_OPACITY * gustScale;
        }
    }

    // -------- Global fade (u_var0) + calm gate --------
    // `activity` zeroes the sand entirely during calm windows; `fade` is the
    // Lua-driven shader in/out.
    distantSandMask *= fade * activity;
    nearSandMask    *= fade * activity;
    gustMask        *= fade * activity;

    // -------- Color grading --------
    // Warm yellow tint, gated by storm activity: during calm windows there is
    // NO tint at all (clean desert air, only heat-haze). Once a storm builds,
    // the tint scales up with intensity so the air reads dusty/hazy yellow.
    vec3  TINT_COLOR     = vec3(1.00, 0.86, 0.55);   // warm sandy yellow
    float tintStrength   = mix(0.05, 0.30, intensity) * fade * activity;
    float darkenAmount   = mix(0.0,  0.20, intensity) * fade * activity;
    float darken         = 1.0 - darkenAmount;

    // Protect only the very brightest highlights (sun, torches) so the yellow
    // covers most of the scene but light sources still punch through.
    float lumMask = 1.0 - smoothstep(0.55, 0.92, mapLum);
    float maskedTintStrength = tintStrength * mix(0.55, 1.0, lumMask);

    vec3 tinted = mix(mapColor.rgb, mapColor.rgb * TINT_COLOR, maskedTintStrength);
    tinted *= darken;

    // -------- Dust haze (global fog) --------
    // Yellow haze that reduces visibility. Gated by activity so calm air is
    // perfectly clear; it ramps in as the storm builds and hard toward the
    // peak. Highlights partially cut through.
    vec3  HAZE_COLOR        = vec3(0.82, 0.68, 0.40);
    float hazeBase          = smoothstep(0.05, 1.0, intensity) * 0.45 * fade * activity;
    float hazeStrength      = hazeBase * mix(0.45, 1.0, lumMask);
    tinted = mix(tinted, HAZE_COLOR, hazeStrength);

    // -------- Dusty vignette (storm "closes in") --------
    vec2 vigUv = screenUv * 2.0 - 1.0;
    vigUv.x *= u_Resolution.x / u_Resolution.y;
    float vigDist = length(vigUv);
    float vigInner = mix(0.55, 0.12, intensity);
    float vigOuter = mix(1.70, 1.20, intensity);
    float vigMask = smoothstep(vigInner, vigOuter, vigDist);
    vigMask = vigMask * vigMask * (3.0 - 2.0 * vigMask);
    float vigAmount = vigMask * smoothstep(0.10, 0.90, intensity) * 0.78 * fade * activity;
    tinted = mix(tinted, HAZE_COLOR, vigAmount);

    // -------- Compose (screen blend) --------
    //   1. tinted map (tint + haze + vignette)
    //   2. distant grains (far + mid) -> then haze again so they sink into fog
    //   3. dust gusts
    //   4. near grains (crisp, closest to camera)
    vec3 sandColor = vec3(0.93, 0.82, 0.55);   // bright grain color

    vec3 distantSandRGB = sandColor * distantSandMask;
    vec3 withDistantSand = 1.0 - (1.0 - tinted) * (1.0 - distantSandRGB);

    withDistantSand = mix(withDistantSand, HAZE_COLOR, hazeStrength * 0.60);

    vec3 gustLayer = GUST_COLOR * gustMask;
    vec3 withGust = 1.0 - (1.0 - withDistantSand) * (1.0 - gustLayer);

    vec3 nearSandRGB = sandColor * nearSandMask;
    vec3 finalRGB = 1.0 - (1.0 - withGust) * (1.0 - nearSandRGB);

    gl_FragColor = vec4(finalRGB, mapColor.a);
}
