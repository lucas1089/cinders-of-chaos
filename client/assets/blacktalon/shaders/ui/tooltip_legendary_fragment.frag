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

    // Legendary: golden glow with sparkles
    vec3 baseColor = vec3(0.96, 0.98, 0.03);
    vec3 goldColor = vec3(1.0, 0.85, 0.2);

    // Vertical gradient (top to bottom fade)
    float gradientFade = 1.0 - v_TexCoord.y;
    gradientFade = gradientFade * gradientFade;

    // Dual pulsing for richness
    float pulse = 0.8 + 0.15 * sin(u_Time * 2.0) + 0.05 * sin(u_Time * 3.5);

    // Flowing golden wave
    float wave = sin(v_TexCoord.x * 6.0 - u_Time * 1.5) * 0.5 + 0.5;

    // Mix yellow-gold
    vec3 finalRgb = mix(baseColor, goldColor, wave * 0.4) * pulse;

    // Add sparkles in top region
    float sparkleRegion = max(0.0, 1.0 - v_TexCoord.y * 2.5);
    if(sparkleRegion > 0.0) {
        for(int i = 0; i < 3; i++) {
            float timeOff = float(i) * 1.3;
            float scale = 20.0 + float(i) * 15.0;
            vec2 gridPos = floor(v_TexCoord * scale) / scale;
            float r = random(gridPos);
            float sparkle = r * sin(u_Time * (2.0 + r * 2.0) + timeOff) * 0.5 + 0.5;
            sparkle = pow(sparkle, 4.0);
            if(sparkle > 0.3) {
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(v_TexCoord, center);
                float sparkleSize = 0.012;
                if(dist < sparkleSize) {
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 2.0);
                    finalRgb += vec3(1.0, 0.95, 0.6) * sparkle * fade * sparkleRegion * 1.5;
                }
            }
        }
    }

    float alpha = gradientFade * 0.4 * textureColor.a;

    gl_FragColor = vec4(finalRgb, alpha) * u_Color;

    if(gl_FragColor.a < 0.01) discard;
}
