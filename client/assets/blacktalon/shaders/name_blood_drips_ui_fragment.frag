// Name Blood Drips (UI variant) - procedural blood drops for the outfit-window
// preview. Drawn as a widget backgroundShader on a strip below the name label,
// it renders falling drops across the whole name width, only in the "blood
// channels" (same CH_W + hash as name_blood_fragment) so the drops line up with
// the streaks running down the previewed name.
//
// Interface (image/background-shader path): v_TexCoord = 0..1 across the widget
// (via u_TextureMatrix), u_WidgetSize = widget pixel size, u_Time = seconds,
// u_Color = tint. Nothing is sampled from u_Tex0.
// BlackTalon MMORPG.

varying vec2 v_TexCoord;
uniform float u_Time;
uniform vec2 u_WidgetSize;
uniform vec4 u_Color;

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

    vec2 p = v_TexCoord * size; // pixel space, y = 0 at the top (under the name)
    float W = size.x;
    float H = size.y;

    float time = mod(u_Time, 6000.0);
    float CH_W = 9.0;                 // MUST match name_blood_fragment.frag CH_W
    float NUM = floor(W / CH_W) + 1.0;

    float field = 0.0;
    float core  = 0.0;

    for (float i = 0.0; i < 24.0; i += 1.0) {
        float active  = step(i, NUM - 0.5);
        float isBlood = step(0.5, hash(i + 3.7)); // SAME channel test as Phase 1
        float on = active * isBlood;

        float r0 = hash(i + 1.3);
        float r1 = hash(i + 5.7);
        float r2 = hash(i + 9.1);

        float colX  = (i + 0.5) * CH_W;
        float baseR = mix(1.6, 2.8, r1);

        // Persistent hanging bead just under the name.
        float pulse = 0.85 + 0.15 * sin(time * 2.0 + r2 * 6.2831);
        float beadR = baseR * (0.65 + 0.25 * pulse);
        vec2  bc = vec2(colX, beadR * 0.6);
        vec2  bd = p - bc;
        float bcontrib = (beadR * beadR) / (dot(bd, bd) + 0.6) * on;
        field += bcontrib;
        core  += bcontrib;

        // Two staggered falling drops per channel.
        for (float k = 0.0; k < 2.0; k += 1.0) {
            float phase = r1 + k * 0.5 + r2 * 0.37;
            float speed = 0.14 + r0 * 0.12;
            float t = fract(time * speed + phase);

            float grow  = smoothstep(0.0, 0.28, t);
            float fallT = clamp((t - 0.28) / 0.72, 0.0, 1.0);

            float rr    = baseR * (0.5 + 0.6 * grow);
            float hangY = baseR * 0.9;
            float y = hangY + (H + baseR * 1.5 - hangY) * (fallT * fallT);
            float stretch = mix(1.0, 1.8, fallT);
            float a = smoothstep(0.0, 0.06, t) * smoothstep(1.0, 0.9, t) * on;

            vec2 c = vec2(colX, y);
            vec2 d = p - c;
            d.y /= stretch;
            float contrib = (rr * rr) / (dot(d, d) + 0.6) * a;
            field += contrib;
            core  += contrib;
        }
    }

    float mask = smoothstep(0.85, 1.25, field);
    if (mask < 0.02) {
        discard;
    }

    vec3 deep   = vec3(0.20, 0.00, 0.00);
    vec3 blood  = vec3(0.50, 0.015, 0.015);
    vec3 bright = vec3(0.82, 0.06, 0.05);
    vec3 sheen  = vec3(1.00, 0.55, 0.50);

    float vy = clamp(p.y / H, 0.0, 1.0);
    vec3 col = mix(blood, deep, smoothstep(0.35, 1.0, vy) * 0.45);
    col = mix(col, bright, smoothstep(1.4, 3.0, core) * 0.5);
    float spec = smoothstep(1.9, 4.0, core);
    col += sheen * spec * 0.3;

    float alpha = clamp(mask, 0.0, 1.0) * u_Color.a;
    gl_FragColor = vec4(col, alpha);
}
