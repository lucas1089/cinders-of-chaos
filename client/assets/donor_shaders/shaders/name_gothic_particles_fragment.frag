// Name Gothic Particles - TINY black specks drifting UP off the top of a single
// letter. One quad per glyph (behind the name). Kept very small on purpose.
// Everything outside the specks is discarded.
//
// Interface: v_TexCoord = 0..1 across the quad (y = 0 top .. 1 bottom, base over
// the letter top), u_WidgetSize = quad pixel size, u_Time = seconds, u_Color =
// tint, u_var0 = per-glyph seed so each letter's specks differ.
// donor client MMORPG.

varying vec2 v_TexCoord;
uniform float u_Time;
uniform vec2 u_WidgetSize;
uniform vec4 u_Color;
uniform float u_var0;

float hash(float n)
{
    return fract(sin(n) * 43758.5453123);
}

void main()
{
    vec2 size = u_WidgetSize;
    if (size.x < 2.0 || size.y < 2.0) {
        discard;
    }

    vec2 uv = v_TexCoord;
    float t = mod(u_Time, 6000.0);
    float seed = u_var0 * 3.71;
    float aspect = size.x / size.y;

    // Many tiny particles rising slowly, drifting a touch sideways.
    float field = 0.0;
    for (int k = 0; k < 12; k++) {
        float fk = float(k);
        float s  = hash(fk + seed);
        float s2 = hash(fk * 1.7 + seed + 3.0);

        float speed = 0.05 + s * 0.05;               // slow rise
        float ph = fract(t * speed + s);             // 0..1 lifetime
        float py = 1.0 - ph;                         // rises: 1 (bottom) -> 0 (top)

        float drift = sin(t * 0.6 + fk + seed) * 0.05;
        float px = 0.5 + (s2 - 0.5) * 0.8 + drift;

        // TINY radius (a couple of pixels at most), shrinking as it rises.
        float rad = mix(0.025, 0.05, s) * (0.7 + 0.3 * ph);
        vec2 d = vec2((uv.x - px) * aspect, uv.y - py);

        float life = smoothstep(0.0, 0.12, ph) * smoothstep(1.0, 0.55, ph);
        field += (rad * rad) / (dot(d, d) + 0.00035) * life;
    }

    // Fully opaque specks (soft edge, but solid at the core).
    float a = smoothstep(0.42, 1.5, field);
    if (a < 0.02) {
        discard;
    }

    // Near-black specks.
    vec3 col = vec3(0.03, 0.03, 0.05);
    gl_FragColor = vec4(col, a * u_Color.a);
}
