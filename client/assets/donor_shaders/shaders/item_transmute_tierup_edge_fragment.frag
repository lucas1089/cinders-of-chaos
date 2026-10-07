// Transmute Result - Tier Up Outline + Inline (golden animated)
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform float u_var0; // intensity (0..1)
varying vec2 v_TexCoord;

const float PI = 3.14159265;

void main()
{
    float intensity = clamp(u_var0, 0.0, 1.0);

    // --- Outline detection (outside the sprite, thick) ---
    float outThickness = 5.0;
    vec2 outSize = outThickness * vec2(1.0 / 512.0);

    float outline = texture2D(u_Tex0, v_TexCoord + vec2(-outSize.x, 0.0)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(0.0, outSize.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(outSize.x, 0.0)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(0.0, -outSize.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(-outSize.x, outSize.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(outSize.x, outSize.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(-outSize.x, -outSize.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(outSize.x, -outSize.y)).a;
    outline = min(outline, 1.0);

    // --- Inline detection (inside the sprite, find pixels near transparency) ---
    float inThickness = 4.0;
    vec2 inSize = inThickness * vec2(1.0 / 512.0);

    float surroundAlpha = texture2D(u_Tex0, v_TexCoord + vec2(-inSize.x, 0.0)).a;
    surroundAlpha += texture2D(u_Tex0, v_TexCoord + vec2(0.0, inSize.y)).a;
    surroundAlpha += texture2D(u_Tex0, v_TexCoord + vec2(inSize.x, 0.0)).a;
    surroundAlpha += texture2D(u_Tex0, v_TexCoord + vec2(0.0, -inSize.y)).a;
    surroundAlpha += texture2D(u_Tex0, v_TexCoord + vec2(-inSize.x, inSize.y)).a;
    surroundAlpha += texture2D(u_Tex0, v_TexCoord + vec2(inSize.x, inSize.y)).a;
    surroundAlpha += texture2D(u_Tex0, v_TexCoord + vec2(-inSize.x, -inSize.y)).a;
    surroundAlpha += texture2D(u_Tex0, v_TexCoord + vec2(inSize.x, -inSize.y)).a;
    surroundAlpha /= 8.0;

    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    float alpha = texColor.a;

    // Inline factor: opaque pixel whose neighbors have some transparency
    float inlineFactor = alpha * clamp(1.0 - surroundAlpha / 0.95, 0.0, 1.0);

    // --- Angle for traveling streaks ---
    vec2 center = vec2(0.5, 0.5);
    vec2 uv = v_TexCoord - center;
    float angle = atan(uv.y, uv.x);
    float normAngle = (angle + PI) / (2.0 * PI);

    // --- Animated streaks ---
    float s1 = pow(sin(normAngle * 8.0 + u_Time * 3.0) * 0.5 + 0.5, 2.0);
    float s2 = pow(sin(normAngle * 6.0 - u_Time * 2.5 + 1.8) * 0.5 + 0.5, 2.0);
    float streaks = s1 * 0.6 + s2 * 0.4;

    // --- Pulse ---
    float pulse = 0.5 + 0.5 * sin(u_Time * 2.5);

    // --- Colors ---
    vec3 gold = vec3(1.0, 0.82, 0.15);
    vec3 hotGold = vec3(1.0, 0.95, 0.55);
    vec3 glowColor = mix(gold, hotGold, streaks * 0.8);
    float brightness = 0.8 + streaks * 0.6;

    // --- Outline color ---
    vec4 outlineColor;
    outlineColor.rgb = glowColor * brightness;
    outlineColor.a = (0.5 + pulse * 0.3 + streaks * 0.2) * intensity;

    // --- Start with base texture ---
    gl_FragColor = texColor;

    // --- Apply outline (transparent pixels adjacent to opaque) ---
    gl_FragColor = mix(gl_FragColor, outlineColor, (outline - gl_FragColor.a) * intensity);

    // --- Apply inline (opaque pixels near border, additive glow) ---
    if (alpha > 0.5) {
        float inlineStrength = inlineFactor * (pulse * 0.5 + streaks * 0.8) * intensity;
        gl_FragColor.rgb += glowColor * inlineStrength * 1.2;

        // Subtle breathing
        float breathe = 0.04 * sin(u_Time * 1.8) + 0.04;
        gl_FragColor.rgb += gl_FragColor.rgb * breathe * intensity;
    }

    if (gl_FragColor.a < 0.01) discard;
}
