// Name Super Saiyan Flames - flame tongues that lick UPWARD off the top of a
// single letter. One of these quads is drawn per glyph (behind the name) by
// Creature::drawInformation, so the flames rise from the letters themselves
// instead of a background box. Everything outside the flame body is discarded.
//
// Interface: v_TexCoord = 0..1 across the quad (y = 0 top .. 1 bottom, the base
// sits over the letter's top), u_WidgetSize = quad pixel size, u_Time = seconds,
// u_Color = tint, u_var0 = per-glyph seed so each letter's flames differ.
// BlackTalon MMORPG.

varying vec2 v_TexCoord;
uniform float u_Time;
uniform vec2 u_WidgetSize;
uniform vec4 u_Color;
uniform float u_var0;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p)
{
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p *= 2.02;
        a *= 0.5;
    }
    return v;
}

void main()
{
    vec2 size = u_WidgetSize;
    if (size.x < 2.0 || size.y < 2.0) {
        discard;
    }

    vec2 uv = v_TexCoord;
    float t = mod(u_Time, 6000.0);
    float seed = u_var0 * 4.13;

    // fy: 0 at the base (bottom, over the letter top) .. 1 at the top of the quad.
    float fy = 1.0 - uv.y;
    float cx = uv.x - 0.5;

    // Per-glyph variation so no two letters' flames look the same.
    float vSpeed = 0.80 + 0.55 * hash(vec2(seed, 2.7)); // rise speed
    float vWidth = mix(0.36, 0.52, hash(vec2(seed, 5.1))); // base width
    float vLean  = (hash(vec2(seed, 8.3)) - 0.5) * 0.20;   // sideways lean

    // Per-column max height that ALSO drifts over time, plus a per-glyph height
    // pulse, so the flames keep changing height instead of holding one shape.
    float colN = fbm(vec2(uv.x * 3.6 + seed * 1.7, seed * 0.7 + t * 0.25));
    float glyphPulse = 0.65 + 0.5 * fbm(vec2(seed * 3.1 + 11.0, t * 0.40));
    float maxH = clamp(mix(0.26, 1.0, colN) * glyphPulse, 0.10, 1.25);

    // Wind: a gentle horizontal sway, stronger toward the tips, mostly shared
    // across letters (a gust passing) with a touch of per-glyph variation.
    float wind = sin(t * 0.9 + uv.y * 3.0) * 0.14 * fy
               + sin(t * 0.6 + seed) * 0.05 * fy;

    // Turbulence, scrolling up (per-glyph speed) so the flames rise gently.
    vec2 sp = vec2(uv.x * 4.5 + seed, uv.y * 5.0 + t * vSpeed + seed);
    float turb = mix(fbm(sp), fbm(sp * 1.8 + 3.0), 0.5);

    // Horizontal taper (leaning + wind), full width at the base, pinching to a tip.
    float halfW = mix(vWidth, 0.05, fy);
    float horiz = smoothstep(halfW, halfW * 0.3, abs(cx - vLean * fy - wind));

    // Flame body: strong at the base, fading up to this column's max height,
    // broken into tongues by turbulence.
    float rise = smoothstep(maxH, maxH * 0.12, fy);
    float flame = horiz * rise * (0.40 + turb * 1.05);
    flame *= smoothstep(0.10, 0.60, turb + fy * 0.25);

    // Gentle, slow flicker (per-glyph phase).
    flame *= 0.9 + 0.1 * sin(t * (2.6 + vSpeed) + turb * 6.2831 + seed);

    float a = smoothstep(0.15, 0.5, flame);
    if (a < 0.02) {
        discard;
    }

    // Heat colour: white/gold hot near the base, cooling to orange/red at the tips.
    float heat = flame * (0.5 + 0.7 * (1.0 - fy));
    vec3 red    = vec3(0.80, 0.06, 0.02);
    vec3 orange = vec3(1.00, 0.42, 0.05);
    vec3 gold   = vec3(1.00, 0.82, 0.15);
    vec3 white  = vec3(1.00, 0.98, 0.82);
    vec3 col = mix(red, orange, smoothstep(0.12, 0.35, heat));
    col = mix(col, gold, smoothstep(0.35, 0.6, heat));
    col = mix(col, white, smoothstep(0.65, 0.9, heat));

    gl_FragColor = vec4(col, a * u_Color.a);
}
