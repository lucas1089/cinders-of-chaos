// Name Chromatic Shader - RGB channel separation (anaglyphic 3D effect)
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

void main()
{
    float time = mod(u_Time, 36000.0);

    // Animated separation distance
    float baseOffset = 0.015;
    float breathe = sin(time * 2.0) * 0.005;
    float separation = baseOffset + breathe;

    // Rotating separation angle
    float angle = time * 1.5;
    vec2 redOffset = vec2(cos(angle), sin(angle)) * separation;
    vec2 blueOffset = vec2(cos(angle + 3.14159), sin(angle + 3.14159)) * separation;

    // Sample each channel at different positions (clamped to valid UV range)
    vec2 uvR = clamp(v_TexCoord + redOffset, vec2(0.0), vec2(1.0));
    vec2 uvB = clamp(v_TexCoord + blueOffset, vec2(0.0), vec2(1.0));
    float r = texture2D(u_Tex0, uvR).r;
    float g = texture2D(u_Tex0, v_TexCoord).g;
    float b = texture2D(u_Tex0, uvB).b;

    // Alpha from all three samples combined
    float ar = texture2D(u_Tex0, uvR).a;
    float ag = texture2D(u_Tex0, v_TexCoord).a;
    float ab = texture2D(u_Tex0, uvB).a;
    float alpha = max(ar, max(ag, ab));

    if (alpha < 0.01) {
        discard;
    }

    // Boost color vibrancy
    vec3 color = vec3(r, g, b);

    // Add subtle prismatic shimmer
    float shimmer = sin(v_TexCoord.x * 15.0 + time * 4.0) * 0.08;
    color.r += shimmer;
    color.b -= shimmer;

    // Boost overall brightness slightly
    color *= 1.15;
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, alpha);
}
