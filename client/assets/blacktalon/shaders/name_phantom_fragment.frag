// Name Phantom Shader - Ghost fade with transparency wave
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 36000.0);

    // Ghostly transparency wave moving across text
    float waveSpeed = 2.0;
    float waveFreq = 4.0;
    float wave = sin(v_TexCoord.x * waveFreq - time * waveSpeed) * 0.5 + 0.5;

    // Secondary slower wave for depth
    float wave2 = sin(v_TexCoord.x * 2.5 + time * 1.2) * 0.5 + 0.5;

    // Combine waves for organic fade pattern
    float fadePattern = wave * 0.6 + wave2 * 0.4;

    // Alpha pulsing - text fades in and out in waves
    float alphaMin = 0.4;
    float alphaMax = 1.0;
    float alpha = mix(alphaMin, alphaMax, fadePattern);

    // Ghostly color palette: white to pale blue to ethereal purple
    vec3 ghostWhite = vec3(0.9, 0.95, 1.0);
    vec3 ghostBlue = vec3(0.6, 0.75, 1.0);
    vec3 ghostPurple = vec3(0.75, 0.6, 1.0);

    // Color shifts with the wave
    float colorPhase = sin(v_TexCoord.x * 3.0 - time * 1.5) * 0.5 + 0.5;
    vec3 ghostColor;
    if (colorPhase < 0.5) {
        ghostColor = mix(ghostBlue, ghostWhite, colorPhase * 2.0);
    } else {
        ghostColor = mix(ghostWhite, ghostPurple, (colorPhase - 0.5) * 2.0);
    }

    // Ethereal glow - brighter parts pulse
    float glow = sin(time * 3.0 + v_TexCoord.x * 5.0) * 0.1 + 0.9;
    ghostColor *= glow;

    // Slight vertical shimmer for spectral effect
    float shimmer = sin(v_TexCoord.y * 30.0 + time * 6.0) * 0.04;
    ghostColor += shimmer;

    // Apply to text
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = ghostColor * (luminance * 0.3 + 0.7);

    gl_FragColor = vec4(finalColor, texColor.a * alpha);
}
