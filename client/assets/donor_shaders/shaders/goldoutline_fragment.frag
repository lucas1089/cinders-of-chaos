varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

float line_thickness = 3.0;

void main()
{
    vec2 size = line_thickness * vec2(1.0 / 512.0, 1.0 / 512.0);

    // Outline detection: sample the 8 neighbours' alpha
    float outline = texture2D(u_Tex0, v_TexCoord + vec2(-size.x, 0.0)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(0.0, size.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, 0.0)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(0.0, -size.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(-size.x, size.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, size.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(-size.x, -size.y)).a;
    outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, -size.y)).a;
    outline = min(outline, 1.0);

    // Bright band sweeping diagonally across the outline (the moving glow)
    float sweep = sin((v_TexCoord.x + v_TexCoord.y) * 6.0 - u_Time * 4.0) * 0.5 + 0.5;
    vec3 warmGold = vec3(0.75, 0.5, 0.12);
    vec3 brightGold = vec3(1.0, 0.92, 0.5);
    vec4 outline_colour = vec4(mix(warmGold, brightGold, sweep), 1.0);

    // Draw only the outline, keep the sprite itself untouched
    gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    gl_FragColor = mix(gl_FragColor, outline_colour, outline - gl_FragColor.a);

    if (gl_FragColor.a < 0.01) discard;
}
