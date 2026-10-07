// Name Pulse Shader - Heartbeat pulse with energy propagation from center
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

    // Distance from center of text (0.5, 0.5)
    float distFromCenter = abs(v_TexCoord.x - 0.5) * 2.0;

    // Heartbeat rhythm: two quick beats then pause
    float beatCycle = mod(time * 1.8, 3.14159 * 2.0);
    float beat1 = pow(max(0.0, sin(beatCycle * 2.0)), 8.0);
    float beat2 = pow(max(0.0, sin(beatCycle * 2.0 - 0.8)), 6.0) * 0.6;
    float heartbeat = beat1 + beat2;

    // Energy wave propagates outward from center
    float waveSpeed = 4.0;
    float waveWidth = 0.3;
    float waveFront = fract(time * 0.8) * 1.5;
    float wave = 1.0 - smoothstep(0.0, waveWidth, abs(distFromCenter - waveFront));
    wave *= step(distFromCenter, waveFront); // Only show behind wave front

    // Color palette: dark crimson to bright red to white at pulse peak
    vec3 darkColor = vec3(0.3, 0.05, 0.08);
    vec3 baseColor = vec3(0.8, 0.1, 0.15);
    vec3 pulseColor = vec3(1.0, 0.4, 0.3);
    vec3 peakColor = vec3(1.0, 0.9, 0.8);

    // Intensity based on heartbeat and wave
    float intensity = 0.3 + heartbeat * 0.5 + wave * 0.4;
    intensity = clamp(intensity, 0.0, 1.0);

    // Map intensity to color
    vec3 color;
    if (intensity < 0.35) {
        color = mix(darkColor, baseColor, intensity / 0.35);
    } else if (intensity < 0.7) {
        color = mix(baseColor, pulseColor, (intensity - 0.35) / 0.35);
    } else {
        color = mix(pulseColor, peakColor, (intensity - 0.7) / 0.3);
    }

    // Apply to text
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = color * (luminance * 0.3 + 0.7);

    // Glow boost during pulse
    finalColor *= (1.0 + heartbeat * 0.3);
    finalColor = clamp(finalColor, 0.0, 1.0);

    gl_FragColor = vec4(finalColor, texColor.a);
}
