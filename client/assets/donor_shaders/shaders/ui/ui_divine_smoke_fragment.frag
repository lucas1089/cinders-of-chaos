// UI Divine Smoke - fragment
// Tooltip rarity "smoke" banner for the Divine (silver) rarity: a clean white
// cloud with a soft drifting highlight and twinkling star sparkles.
// Pairs with ui_prismatic_vertex (provides normalized v_TexCoord).
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;

varying vec2 v_TexCoord;

float rand(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec4 tex = texture2D(u_Tex0, v_TexCoord);

    // Soft drifting highlight: brighter core that slides left<->right.
    float sweep = 0.72 + 0.30 * sin(v_TexCoord.x * 3.14159265 - u_Time * 1.1);
    vec3 col = vec3(sweep);

    // Twinkling star sparkles scattered across the banner (larger & brighter).
    float sp = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        vec2 p = vec2(rand(vec2(fi, 1.3)), rand(vec2(fi, 7.7)));
        float tw = pow(0.5 + 0.5 * sin(u_Time * 3.0 + fi * 1.9), 2.0);
        vec2 d = (v_TexCoord - p) / 0.10;
        float core = smoothstep(1.0, 0.0, length(d));
        float rays = smoothstep(1.0, 0.0, abs(d.y)) * smoothstep(6.0, 0.0, abs(d.x))
                   + smoothstep(1.0, 0.0, abs(d.x)) * smoothstep(6.0, 0.0, abs(d.y));
        sp += (core + rays * 0.7) * tw;
    }
    col += vec3(1.0) * sp * 1.5;

    gl_FragColor = vec4(col, tex.a) * u_Color;
}
