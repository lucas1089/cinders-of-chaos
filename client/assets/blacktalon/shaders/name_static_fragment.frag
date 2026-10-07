// Name Static Shader - TV static noise overlay on text
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// High-frequency noise
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 36000.0);

    // TV static noise - changes every frame
    float staticNoise = noise(v_TexCoord * 200.0 + vec2(time * 100.0, time * 73.0));
    float staticNoise2 = noise(v_TexCoord * 80.0 + vec2(time * 50.0, time * 37.0));

    // Combine different noise frequencies
    float combinedNoise = staticNoise * 0.6 + staticNoise2 * 0.4;

    // Occasional horizontal distortion lines (VHS effect)
    float lineNoise = step(0.97, noise(vec2(floor(v_TexCoord.y * 30.0), floor(time * 8.0))));
    float hShift = lineNoise * (noise(vec2(time * 5.0, v_TexCoord.y)) - 0.5) * 0.03;

    // Sample with horizontal shift (clamped to valid UV range)
    vec2 uv = v_TexCoord;
    uv.x += hShift;
    uv = clamp(uv, vec2(0.0), vec2(1.0));
    vec4 shiftedColor = texture2D(u_Tex0, uv);

    // Use shifted sample when line is active
    vec4 baseColor = mix(texColor, shiftedColor, lineNoise);

    // Base color: silver/gray with slight warm tint
    float luminance = dot(baseColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 silverBase = vec3(0.85, 0.83, 0.88);
    vec3 warmTint = vec3(0.95, 0.9, 0.85);

    // Animate between silver and warm tones
    float tintPhase = sin(time * 1.5 + v_TexCoord.x * 4.0) * 0.5 + 0.5;
    vec3 baseTextColor = mix(silverBase, warmTint, tintPhase);

    // Apply static noise overlay
    float noiseStrength = 0.25;
    vec3 finalColor = baseTextColor * (luminance * 0.4 + 0.6);
    finalColor = mix(finalColor, vec3(combinedNoise), noiseStrength);

    // Occasional bright flash (interference)
    float flashChance = step(0.985, noise(vec2(floor(time * 3.0), 42.0)));
    float flash = flashChance * 0.3;
    finalColor += flash;

    // Vertical hold wobble
    float wobble = sin(time * 0.3) * 0.01;
    finalColor *= (1.0 + wobble);

    finalColor = clamp(finalColor, 0.0, 1.0);

    gl_FragColor = vec4(finalColor, baseColor.a);
}
