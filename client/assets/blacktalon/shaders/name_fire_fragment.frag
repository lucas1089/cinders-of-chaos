// Name Fire Shader - Red/orange animated gradient for text rendering
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Simple noise function for fire turbulence
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float smoothNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = noise(i);
    float b = noise(i + vec2(1.0, 0.0));
    float c = noise(i + vec2(0.0, 1.0));
    float d = noise(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only process visible text pixels
    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Create fire turbulence effect
    vec2 noiseCoord = v_TexCoord * 4.0;
    noiseCoord.y -= time * 2.0;  // Fire rises upward

    float turbulence = smoothNoise(noiseCoord) * 0.5 +
                       smoothNoise(noiseCoord * 2.0) * 0.25 +
                       smoothNoise(noiseCoord * 4.0) * 0.125;

    // Animated intensity based on position
    float intensity = sin(v_TexCoord.x * 10.0 + time * 5.0) * 0.2 + 0.8;
    intensity += turbulence * 0.3;

    // Fire color gradient: dark red -> red -> orange -> yellow
    vec3 darkRed = vec3(0.5, 0.0, 0.0);
    vec3 red = vec3(1.0, 0.2, 0.0);
    vec3 orange = vec3(1.0, 0.5, 0.0);
    vec3 yellow = vec3(1.0, 0.9, 0.3);

    // Create animated color gradient
    float colorPhase = sin(v_TexCoord.x * 6.0 - time * 4.0 + turbulence * 3.0) * 0.5 + 0.5;

    vec3 fireColor;
    if (colorPhase < 0.33) {
        fireColor = mix(darkRed, red, colorPhase * 3.0);
    } else if (colorPhase < 0.66) {
        fireColor = mix(red, orange, (colorPhase - 0.33) * 3.0);
    } else {
        fireColor = mix(orange, yellow, (colorPhase - 0.66) * 3.0);
    }

    // Apply to text
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = fireColor * intensity * (luminance * 0.4 + 0.6);

    gl_FragColor = vec4(finalColor, texColor.a);
}
