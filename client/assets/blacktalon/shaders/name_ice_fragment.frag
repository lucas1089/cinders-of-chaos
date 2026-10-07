// Name Ice Shader - Blue/cyan gradient for text rendering
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Crystalline noise for ice effect
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only process visible text pixels
    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Ice color palette
    vec3 deepBlue = vec3(0.1, 0.2, 0.5);
    vec3 iceBlue = vec3(0.3, 0.6, 0.9);
    vec3 cyan = vec3(0.4, 0.8, 1.0);
    vec3 white = vec3(0.9, 0.95, 1.0);

    // Create slow, shimmering ice effect
    float shimmer = sin(v_TexCoord.x * 15.0 + time * 1.5) * 0.5 + 0.5;
    shimmer *= sin(v_TexCoord.y * 12.0 - time * 0.8) * 0.5 + 0.5;

    // Add crystalline sparkle
    float sparkle = noise(v_TexCoord * 50.0 + time * 0.5);
    sparkle = pow(sparkle, 8.0);  // Make sparkles sharp and rare

    // Gentle wave animation
    float wave = sin(v_TexCoord.x * 8.0 + v_TexCoord.y * 4.0 + time * 2.0) * 0.5 + 0.5;

    // Blend ice colors
    vec3 iceColor;
    float blendFactor = wave * 0.7 + shimmer * 0.3;

    if (blendFactor < 0.33) {
        iceColor = mix(deepBlue, iceBlue, blendFactor * 3.0);
    } else if (blendFactor < 0.66) {
        iceColor = mix(iceBlue, cyan, (blendFactor - 0.33) * 3.0);
    } else {
        iceColor = mix(cyan, white, (blendFactor - 0.66) * 3.0);
    }

    // Add sparkle highlights
    iceColor = mix(iceColor, white, sparkle * 0.8);

    // Apply to text
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = iceColor * (luminance * 0.3 + 0.7);

    gl_FragColor = vec4(finalColor, texColor.a);
}
