// Name Blood Drips - procedural blood drops that well up under a single LETTER
// and fall away below it. One of these quads is drawn per glyph of a name using
// the "Blood" name shader (spaces get none), so blood only falls from actual
// letters. Everything outside the drop shapes is discarded.
//
// Interface: v_TexCoord = 0..1 across the quad (y = 0 at the top, next to the
// letter), u_Time = seconds, u_WidgetSize = quad pixel size, u_Color = tint
// (alpha carries the name's distance fade), u_var0 = per-glyph seed so each
// letter drips independently.
//
// Technique: a metaball field. Each column carries a persistent hanging bead
// (blood welling under the letter) plus a couple of staggered falling drops.
// Summing 1/dist^2 kernels merges neighbours like a liquid; the field is
// thresholded for the shape and its density drives the wet/bright core shading.
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

    // Pixel-space coordinates, y = 0 at the top (right under the letter).
    vec2 p = v_TexCoord * size;
    float W = size.x;
    float H = size.y;

    float time = mod(u_Time, 6000.0);
    float seed = u_var0 * 3.17; // per-glyph offset so letters differ

    // 1-2 drip columns depending on how wide the letter is.
    float NUM = clamp(floor(W / 6.0), 1.0, 2.0);

    float field = 0.0; // metaball field -> alpha / shape
    float core  = 0.0; // denser accumulation near drop centers -> wet shading

    for (float i = 0.0; i < 2.0; i += 1.0) {
        float active = step(i, NUM - 0.5); // 1 for columns [0, NUM-1], else 0

        float r0 = hash(i + 1.3 + seed);
        float r1 = hash(i + 5.7 + seed);
        float r2 = hash(i + 9.1 + seed);

        // Column x within the letter, with a little lateral jitter.
        float colX  = (i + 0.5) / NUM * W + (r0 - 0.5) * (W / NUM) * 0.25;
        float baseR = mix(1.5, 2.6, r1);

        // Persistent hanging bead just under the letter (gently pulsing).
        float pulse = 0.85 + 0.15 * sin(time * 2.0 + r2 * 6.2831);
        float beadR = baseR * (0.65 + 0.25 * pulse);
        vec2  bc = vec2(colX, beadR * 0.6);
        vec2  bd = p - bc;
        float bdist2 = dot(bd, bd) + 0.6;
        float bcontrib = (beadR * beadR) / bdist2 * active;
        field += bcontrib;
        core  += bcontrib;

        // Two staggered falling drops per column for continuous dripping.
        for (float k = 0.0; k < 2.0; k += 1.0) {
            float phase = r1 + k * 0.5 + r2 * 0.37;
            float speed = 0.14 + r0 * 0.12;
            float t = fract(time * speed + phase);

            float grow  = smoothstep(0.0, 0.28, t);
            float fallT = clamp((t - 0.28) / 0.72, 0.0, 1.0);

            float rr    = baseR * (0.5 + 0.6 * grow);
            float hangY = baseR * 0.9;
            // Gravity: quadratic acceleration downward past the hang point.
            float y = hangY + (H + baseR * 1.5 - hangY) * (fallT * fallT);

            // Teardrop vertical stretch while falling.
            float stretch = mix(1.0, 1.8, fallT);

            // Fade in on spawn, out as it leaves the bottom.
            float a = smoothstep(0.0, 0.06, t) * smoothstep(1.0, 0.9, t) * active;

            vec2 c = vec2(colX, y);
            vec2 d = p - c;
            d.y /= stretch;
            float dist2 = dot(d, d) + 0.6;
            float contrib = (rr * rr) / dist2 * a;
            field += contrib;
            core  += contrib;
        }
    }

    float mask = smoothstep(0.85, 1.25, field);
    if (mask < 0.02) {
        discard;
    }

    // --- Blood coloring ---
    vec3 deep   = vec3(0.20, 0.00, 0.00);
    vec3 blood  = vec3(0.50, 0.015, 0.015);
    vec3 bright = vec3(0.82, 0.06, 0.05);
    vec3 sheen  = vec3(1.00, 0.55, 0.50);

    float vy = clamp(p.y / H, 0.0, 1.0);
    vec3 col = mix(blood, deep, smoothstep(0.35, 1.0, vy) * 0.45);

    // Denser field = closer to a drop core = wetter / brighter, with a specular.
    col = mix(col, bright, smoothstep(1.4, 3.0, core) * 0.5);
    float spec = smoothstep(1.9, 4.0, core);
    col += sheen * spec * 0.3;

    float alpha = clamp(mask, 0.0, 1.0) * u_Color.a;
    gl_FragColor = vec4(col, alpha);
}
