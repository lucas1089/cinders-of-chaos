uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;
varying vec2 v_Position;

// Pseudo-random for sparkles
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main()
{
    vec4 textureColor = texture2D(u_Tex0, v_TexCoord);

    // Mythic: purple with shifting hues and intense sparkles
    vec3 baseColor = vec3(0.64, 0.06, 0.96);
    vec3 accentColor = vec3(0.9, 0.2, 1.0);
    vec3 blueAccent = vec3(0.4, 0.1, 1.0);

    // Vertical gradient (top to bottom fade)
    float gradientFade = 1.0 - v_TexCoord.y;
    gradientFade = gradientFade * gradientFade;

    // Dual pulsing
    float pulse = 0.75 + 0.2 * sin(u_Time * 2.0) + 0.05 * sin(u_Time * 4.0);

    // Color shifting wave between purple and blue
    float wave = sin(v_TexCoord.x * 5.0 - u_Time * 1.8) * 0.5 + 0.5;
    float wave2 = sin(v_TexCoord.x * 9.0 + u_Time * 1.2) * 0.5 + 0.5;

    // Mix three colors for rich shifting effect
    vec3 finalRgb = mix(baseColor, accentColor, wave * 0.4);
    finalRgb = mix(finalRgb, blueAccent, wave2 * 0.25);
    finalRgb *= pulse;

    // Bright glow at top
    float topGlow = max(0.0, 1.0 - v_TexCoord.y * 3.0);
    finalRgb += accentColor * topGlow * 0.25;

    // Sparkles throughout
    float sparkleRegion = max(0.0, 1.0 - v_TexCoord.y * 2.0);
    if(sparkleRegion > 0.0) {
        for(int i = 0; i < 4; i++) {
            float timeOff = float(i) * 1.1;
            float scale = 18.0 + float(i) * 12.0;
            vec2 gridPos = floor(v_TexCoord * scale) / scale;
            float r = random(gridPos);
            float sparkle = r * sin(u_Time * (1.5 + r * 3.0) + timeOff) * 0.5 + 0.5;
            sparkle = pow(sparkle, 3.5);
            if(sparkle > 0.25) {
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(v_TexCoord, center);
                float sparkleSize = 0.01;
                if(dist < sparkleSize) {
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 2.0);
                    // Purple-white sparkles
                    vec3 sparkleColor = vec3(0.9, 0.7, 1.0);
                    finalRgb += sparkleColor * sparkle * fade * sparkleRegion * 1.8;
                }
            }
        }
    }

    float alpha = gradientFade * 0.45 * textureColor.a;

    gl_FragColor = vec4(finalRgb, alpha) * u_Color;

    if(gl_FragColor.a < 0.01) discard;
}
