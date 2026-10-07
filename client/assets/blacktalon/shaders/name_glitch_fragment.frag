// Name Glitch Shader - Digital corruption with chromatic aberration
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Hash-based pseudo-random
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

void main()
{
    float time = mod(u_Time, 36000.0);

    // Glitch timing - create bursts of glitching
    float glitchSpeed = 6.0;
    float glitchCycle = fract(time * 0.5);
    float glitchIntensity = step(0.75, glitchCycle) * (1.0 - smoothstep(0.75, 1.0, glitchCycle));

    // Random horizontal displacement per scanline
    float lineHash = hash(floor(v_TexCoord.y * 20.0) + floor(time * glitchSpeed));
    float displacement = (lineHash - 0.5) * 0.08 * glitchIntensity;

    // Occasional large block shift
    float blockHash = hash(floor(time * 3.0));
    float blockY = step(0.85, blockHash);
    float blockShift = blockY * (hash(floor(time * 7.0)) - 0.5) * 0.15;

    // Apply displacement to UV
    vec2 uv = v_TexCoord;
    uv.x += displacement + blockShift;
    uv = clamp(uv, vec2(0.0), vec2(1.0));

    // Chromatic aberration - split RGB channels
    float aberration = 0.012 + glitchIntensity * 0.025;
    vec2 uvR = clamp(uv + vec2(aberration, 0.0), vec2(0.0), vec2(1.0));
    vec2 uvB = clamp(uv - vec2(aberration, 0.0), vec2(0.0), vec2(1.0));
    float r = texture2D(u_Tex0, uvR).r;
    float g = texture2D(u_Tex0, uv).g;
    float b = texture2D(u_Tex0, uvB).b;
    float a = texture2D(u_Tex0, uv).a;

    // Also sample alpha from shifted positions to avoid edge artifacts
    float ar = texture2D(u_Tex0, uvR).a;
    float ab = texture2D(u_Tex0, uvB).a;
    a = max(a, max(ar, ab));

    if (a < 0.01) {
        discard;
    }

    // Color tint cycling between cyan and magenta during glitch
    vec3 color = vec3(r, g, b);
    float tint = sin(time * 8.0) * 0.5 + 0.5;
    vec3 glitchColor = mix(vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 1.0), tint);
    color = mix(color, color * glitchColor, glitchIntensity * 0.5);

    // Scanline effect
    float scanline = sin(v_TexCoord.y * 80.0 + time * 10.0) * 0.03;
    color += scanline * glitchIntensity;

    // Base color when not glitching - subtle cyan tint
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 baseColor = mix(color, vec3(0.7, 1.0, 1.0) * luminance, 0.3 * (1.0 - glitchIntensity));
    color = mix(baseColor, color, glitchIntensity);

    gl_FragColor = vec4(color, a);
}
