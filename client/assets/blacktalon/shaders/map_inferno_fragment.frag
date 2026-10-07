uniform sampler2D u_Tex0;          // map framebuffer
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;
uniform float u_var0;              // global fade amount, 0 = no effect, 1 = full
uniform float u_heat;             // proximity heat 0..1 (driven from Lua near lava);
                                  // 0 = base ambient, 1 = lots of fire near lava

// ============================================================================
// map_inferno — Satan Citadel ambience (fully procedural)
// ============================================================================
// Two LIGHT layers, tuned to NOT obstruct gameplay:
//   1. Heat-haze shimmer confined to the screen EDGES (clean center circle),
//      same idea as map_sandstorm_v2 — the air ripples around the borders.
//   2. A FEW small fire particles (embers) that rise from the floor toward the
//      top. They are sparse in space AND in time: each particle slot only
//      emits on some cycles and waits between emissions, so most of the time
//      only one or two embers are drifting up — never a steady stream. Their
//      horizontal drift, spawn position, speed and flicker are all randomized
//      per emission, so they look uncoordinated.
//
// All effects are multiplied by `fade` (u_var0) so Lua can ease it in/out.

// ---------------------------------------------------------------------------
// Tunables
// ---------------------------------------------------------------------------
const int   NUM_PARTICLES  = 30;     // slots (NOT how many are visible at once) —
                                     // headroom so surges near lava show MANY more
const float EMIT_SKIP      = 0.62;   // higher = rarer emissions (fewer on screen)
const float LIFE           = 4.2;    // seconds a particle takes to rise
const float PERIOD_MIN     = 9.0;    // min gap between a slot's emissions (s)
const float PERIOD_MAX     = 16.0;   // max gap between a slot's emissions (s)

// Surge cycle — occasional BURSTS of extra flames. Gated by heat so it ONLY
// happens near lava; far from the lava there is no surge at all.
const float SURGE_PERIOD   = 6.0;    // seconds per surge cycle
const float SURGE_SKIP     = 0.45;   // higher = fewer cycles actually surge
const float SURGE_GATE_LO  = 0.15;   // heat below this = no surge (not near lava)
const float SURGE_GATE_HI  = 0.55;   // heat above this = full surge strength

const float FIRE_TOP       = 0.70;   // how high embers rise (fraction of screen)
const float SPAWN_Y        = 0.03;   // where they spawn (just above the floor)
const float EMBER_SIZE     = 0.016;  // ember radius (fraction of screen height)
const float EMBER_BRIGHT   = 0.85;   // per-ember brightness
const float SWAY_AMOUNT    = 0.025;  // horizontal drift while rising

// Ember palette: hot yellow core near the floor -> orange -> red at the top.
const vec3  EMBER_HOT      = vec3(1.00, 0.80, 0.35);
const vec3  EMBER_COOL     = vec3(0.95, 0.25, 0.05);

// If embers spawn at the TOP / fall instead of rise (framebuffer Y), flip to 1.
const float FLIP_Y         = 0.0;

// ---------------------------------------------------------------------------
// Hashes
// ---------------------------------------------------------------------------
float h11(float x)  { return fract(sin(x * 127.1) * 43758.5453); }
float h21(vec2 p)   { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// ---------------------------------------------------------------------------
// Edge-only heat-haze (clean center circle, same as map_sandstorm_v2)
// ---------------------------------------------------------------------------
vec2 heatHaze(vec2 uv) {
    // Stronger heat wave that intensifies with proximity heat (u_heat).
    // Higher spatial frequencies -> tighter, smaller ripples (style "2").
    float h = clamp(u_heat, 0.0, 1.0);
    float amp = mix(0.0011, 0.0024, h);
    float wx = sin(uv.y * 40.0 + u_Time * 1.4) * amp
             + sin(uv.y * 22.0 - u_Time * 0.9) * amp * 0.5;
    float wy = sin(uv.x * 32.0 + u_Time * 1.1) * amp * 0.6;
    return vec2(wx, wy);
}

void main() {
    float fade = clamp(u_var0, 0.0, 1.0);
    float heat = clamp(u_heat, 0.0, 1.0);

    // ---- Surge cycle: occasional bursts of EXTRA flames, only near lava ----
    // A pulse fires on some cycles (quick rise, slow fall). It is multiplied by
    // a heat gate, so when you're NOT near lava (heat low) surge is 0 and the
    // cycle does nothing; near the lava the bursts kick in on top of the heat.
    float sPh   = u_Time / SURGE_PERIOD;
    float sCyc  = floor(sPh);
    float sFrac = fract(sPh);
    float pulse = smoothstep(0.0, 0.15, sFrac) * (1.0 - smoothstep(0.30, 1.0, sFrac));
    float sFire = step(SURGE_SKIP, h11(sCyc * 1.37 + 0.7));   // only some cycles surge
    float surge = pulse * sFire * smoothstep(SURGE_GATE_LO, SURGE_GATE_HI, heat);

    // Heat (lava proximity) ramps the fire up; the surge pushes it further into
    // a burst. At heat = 0 it's the base sparse ambient look (no surge).
    float emitSkip    = mix(EMIT_SKIP, 0.12, heat) - surge * 0.12;
    emitSkip          = max(emitSkip, 0.0);
    float fireTop     = mix(FIRE_TOP, 0.85, heat) + surge * 0.05;
    float emberBright = mix(EMBER_BRIGHT, EMBER_BRIGHT * 1.7, heat) * (1.0 + surge * 0.6);

    // Screen-space UV anchored to the VIEWPORT (gl_FragCoord), NOT to the map.
    // The heat-haze phase and edge mask are computed from this so they stay put
    // on screen when the player walks (using v_TexCoord makes the pattern slide
    // with the scrolling map -> looks like it accelerates while moving).
    vec2 screenUv = gl_FragCoord.xy / u_Resolution;
    float aspect  = u_Resolution.x / u_Resolution.y;

    // ---- Edge mask: 0 in the central circle, 1 toward the borders ----
    vec2  edgeUv   = (screenUv * 2.0 - 1.0);
    edgeUv.x      *= aspect;
    float edgeDist = length(edgeUv);
    float edgeMask = smoothstep(0.40, 1.15, edgeDist);

    // ---- Heat-haze (edges only) -> wobble the map UV before sampling ----
    // Phase from screenUv (viewport-anchored); offset still applied to v_TexCoord.
    vec2 mapUv = v_TexCoord + heatHaze(screenUv) * edgeMask * fade;
    vec4 mapColor = texture2D(u_Tex0, mapUv);

    // ---- Floor/top split for the rising particles. ----
    float sy = mix(screenUv.y, 1.0 - screenUv.y, FLIP_Y);
    float sx = screenUv.x;

    // ---- Rising fire particles ----
    float emberAccum = 0.0;
    vec3  emberColor = vec3(0.0);

    for (int i = 0; i < NUM_PARTICLES; i++) {
        float fi = float(i);
        float seed = h11(fi * 3.71 + 1.3);

        // Each slot emits on its own period with a random phase, so slots are
        // staggered and uncoordinated. period >> LIFE => long quiet gaps.
        float period = mix(PERIOD_MIN, PERIOD_MAX, h11(fi * 1.7 + 0.2));
        float t      = u_Time + seed * 137.0;
        float cyc    = floor(t / period);
        float localT = fract(t / period) * period;   // seconds into this cycle

        // Only the first LIFE seconds of the cycle are the rise; the rest is a
        // quiet gap. And only SOME cycles emit at all (sparse in time).
        float emitRoll = h21(vec2(fi, cyc) * 1.91 + 0.5);
        float rising   = step(localT, LIFE) * step(emitSkip, emitRoll);
        float progress = clamp(localT / LIFE, 0.0, 1.0);   // 0 floor -> 1 top

        // Random spawn X per emission + uncoordinated horizontal sway as it
        // rises (two incommensurate wobbles).
        float spawnX = h21(vec2(fi * 5.3, cyc * 2.17));
        float sway   = sin(progress * 6.0  + seed * 24.0) * SWAY_AMOUNT
                     + sin(progress * 13.7 + seed * 7.0)  * SWAY_AMOUNT * 0.5;
        float px = spawnX + sway;
        float py = mix(SPAWN_Y, fireTop, progress);

        // Brightness: fade in at spawn, fade out near the top, plus flicker.
        float env = smoothstep(0.0, 0.12, progress)
                  * (1.0 - smoothstep(0.65, 1.0, progress));
        float flicker = 0.7 + 0.3 * sin(u_Time * 14.0 + seed * 40.0);

        // Soft ember disc, slightly stretched vertically to read as a flame.
        vec2 d = vec2((sx - px) * aspect, (sy - py) * 0.75);
        float dist = length(d);
        float disc = smoothstep(EMBER_SIZE, EMBER_SIZE * 0.25, dist);

        float e = disc * env * flicker * rising;
        emberAccum += e;
        emberColor += mix(EMBER_HOT, EMBER_COOL, progress) * e;
    }

    // Normalize the accumulated color by total weight (avoid double-bright
    // overlaps washing to white), then scale by brightness + fade.
    vec3 embers = (emberAccum > 0.001 ? emberColor / emberAccum : vec3(0.0))
                  * clamp(emberAccum, 0.0, 1.0) * emberBright * fade;

    // ---- Compose (screen blend so it only brightens) ----
    vec3 col = mapColor.rgb;
    col = 1.0 - (1.0 - col) * (1.0 - embers);

    gl_FragColor = vec4(col, mapColor.a);
}
