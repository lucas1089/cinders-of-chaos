// Name Neon Shader - Colorful glow effect for text rendering
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only process visible text pixels
    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Neon color palette - vibrant colors
    vec3 pink = vec3(1.0, 0.2, 0.8);
    vec3 purple = vec3(0.6, 0.2, 1.0);
    vec3 blue = vec3(0.2, 0.4, 1.0);
    vec3 cyan = vec3(0.0, 1.0, 0.9);
    vec3 green = vec3(0.2, 1.0, 0.4);

    // Create color cycling effect
    float cycleSpeed = 1.5;
    float phase = v_TexCoord.x * 3.0 + time * cycleSpeed;
    float cyclePhase = fract(phase / 6.283185);  // Normalize to 0-1

    // Smooth color transitions through neon palette
    vec3 neonColor;
    if (cyclePhase < 0.2) {
        neonColor = mix(pink, purple, cyclePhase * 5.0);
    } else if (cyclePhase < 0.4) {
        neonColor = mix(purple, blue, (cyclePhase - 0.2) * 5.0);
    } else if (cyclePhase < 0.6) {
        neonColor = mix(blue, cyan, (cyclePhase - 0.4) * 5.0);
    } else if (cyclePhase < 0.8) {
        neonColor = mix(cyan, green, (cyclePhase - 0.6) * 5.0);
    } else {
        neonColor = mix(green, pink, (cyclePhase - 0.8) * 5.0);
    }

    // Add pulsing glow effect
    float pulse = sin(time * 4.0) * 0.15 + 0.85;

    // Add electric flicker
    float flicker = sin(time * 20.0 + v_TexCoord.x * 30.0) * 0.05 + 0.95;

    // Boost brightness for neon glow look
    float glowIntensity = 1.2;
    neonColor *= glowIntensity * pulse * flicker;

    // Add white core for intense glow effect
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float coreIntensity = pow(luminance, 0.5);  // Brighten core
    vec3 whiteCore = vec3(1.0, 1.0, 1.0);

    // Blend neon color with white core
    vec3 finalColor = mix(neonColor, whiteCore, coreIntensity * 0.3);
    finalColor *= (luminance * 0.2 + 0.8);

    // Ensure colors stay vibrant (prevent over-saturation)
    finalColor = clamp(finalColor, 0.0, 1.0);

    gl_FragColor = vec4(finalColor, texColor.a);
}
