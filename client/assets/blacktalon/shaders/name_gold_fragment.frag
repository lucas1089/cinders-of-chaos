// Name Gold Shader - Golden shimmer effect for text rendering
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

    // Gold color palette
    vec3 darkGold = vec3(0.6, 0.4, 0.1);
    vec3 gold = vec3(1.0, 0.84, 0.0);
    vec3 brightGold = vec3(1.0, 0.9, 0.4);
    vec3 white = vec3(1.0, 1.0, 0.9);

    // Create sweeping shimmer effect (like light reflecting off gold)
    float shimmerSpeed = 2.0;
    float shimmerWidth = 0.15;

    // Moving highlight position
    float highlightPos = fract(time * shimmerSpeed * 0.1);
    float distToHighlight = abs(v_TexCoord.x - highlightPos);

    // Wrap around effect
    distToHighlight = min(distToHighlight, 1.0 - distToHighlight);

    // Sharp shimmer peak
    float shimmer = 1.0 - smoothstep(0.0, shimmerWidth, distToHighlight);
    shimmer = pow(shimmer, 2.0);

    // Secondary subtle wave
    float wave = sin(v_TexCoord.x * 12.0 + time * 3.0) * 0.5 + 0.5;
    wave *= sin(v_TexCoord.y * 8.0 - time * 1.5) * 0.5 + 0.5;

    // Combine effects
    float intensity = wave * 0.3 + 0.5;
    intensity += shimmer * 0.5;

    // Blend gold colors based on intensity
    vec3 goldColor;
    if (intensity < 0.4) {
        goldColor = mix(darkGold, gold, intensity * 2.5);
    } else if (intensity < 0.7) {
        goldColor = mix(gold, brightGold, (intensity - 0.4) * 3.33);
    } else {
        goldColor = mix(brightGold, white, (intensity - 0.7) * 3.33);
    }

    // Apply metallic sheen
    float sheen = pow(shimmer, 3.0);
    goldColor = mix(goldColor, white, sheen * 0.6);

    // Apply to text
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = goldColor * (luminance * 0.3 + 0.7);

    gl_FragColor = vec4(finalColor, texColor.a);
}
