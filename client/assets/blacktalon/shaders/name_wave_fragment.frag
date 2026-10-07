// Name Wave Shader - Sinusoidal UV distortion making text undulate
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

void main()
{
    float time = mod(u_Time, 36000.0);

    // Sinusoidal distortion on UV coordinates
    vec2 uv = v_TexCoord;

    // Primary wave - horizontal undulation
    float waveAmplitude = 0.015;
    float waveFrequency = 8.0;
    float waveSpeed = 3.0;
    uv.y += sin(uv.x * waveFrequency + time * waveSpeed) * waveAmplitude;

    // Secondary wave - vertical ripple
    float rippleAmplitude = 0.008;
    float rippleFrequency = 12.0;
    uv.x += sin(uv.y * rippleFrequency - time * 2.5) * rippleAmplitude;
    uv = clamp(uv, vec2(0.0), vec2(1.0));

    vec4 texColor = texture2D(u_Tex0, uv);

    if (texColor.a < 0.01) {
        discard;
    }

    // Ocean-inspired color palette
    vec3 deepBlue = vec3(0.1, 0.2, 0.6);
    vec3 seaGreen = vec3(0.1, 0.7, 0.6);
    vec3 aqua = vec3(0.3, 0.9, 0.9);
    vec3 foam = vec3(0.85, 0.95, 1.0);

    // Color follows the wave pattern
    float colorWave = sin(uv.x * 5.0 - time * 2.0) * 0.5 + 0.5;
    float colorWave2 = sin(uv.x * 3.0 + time * 1.5) * 0.5 + 0.5;
    float colorMix = colorWave * 0.7 + colorWave2 * 0.3;

    vec3 waveColor;
    if (colorMix < 0.33) {
        waveColor = mix(deepBlue, seaGreen, colorMix * 3.0);
    } else if (colorMix < 0.66) {
        waveColor = mix(seaGreen, aqua, (colorMix - 0.33) * 3.0);
    } else {
        waveColor = mix(aqua, foam, (colorMix - 0.66) * 3.0);
    }

    // Crest highlight - foam-like brightness at wave peaks
    float crest = pow(max(0.0, sin(uv.x * waveFrequency + time * waveSpeed)), 4.0);
    waveColor = mix(waveColor, foam, crest * 0.4);

    // Apply to text
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = waveColor * (luminance * 0.3 + 0.7);

    gl_FragColor = vec4(finalColor, texColor.a);
}
