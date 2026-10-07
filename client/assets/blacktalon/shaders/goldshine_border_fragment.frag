varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

void main()
{
    vec4 tex = texture2D(u_Tex0, v_TexCoord);

    // Bright band travelling along the border (vertical shimmer)
    float shine = sin(v_TexCoord.y * 8.0 - u_Time * 4.0) * 0.5 + 0.5;

    vec3 gold = vec3(1.0, 0.85, 0.35);
    vec3 darkGold = vec3(0.5, 0.36, 0.1);
    vec3 color = mix(darkGold, gold, shine);

    // Keep the texture's alpha so only the border shape is drawn (center stays transparent)
    gl_FragColor = vec4(color, tex.a);
}
