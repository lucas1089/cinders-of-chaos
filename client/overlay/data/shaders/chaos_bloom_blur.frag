// Cinders of Chaos: one pass of the soft glow's separable blur (game_visualfx; base patch 0132). A 9 tap Gaussian done with 5
// bilinear reads; the engine draws it twice, u_Params.xy = (1 / width, 0) then (0, 1 / height) of the small buffer, so the halo
// reaches about 13 screen pixels. The weights add up to 1: the blur only spreads the bright pass, it adds no light.
uniform sampler2D u_Tex0;
uniform vec4 u_Params;
varying vec2 v_TexCoord;

void main()
{
    vec2 d = u_Params.xy;
    vec3 s = texture2D(u_Tex0, v_TexCoord).rgb * 0.2270270270;
    s += (texture2D(u_Tex0, v_TexCoord + d * 1.3846153846).rgb + texture2D(u_Tex0, v_TexCoord - d * 1.3846153846).rgb) * 0.3162162162;
    s += (texture2D(u_Tex0, v_TexCoord + d * 3.2307692308).rgb + texture2D(u_Tex0, v_TexCoord - d * 3.2307692308).rgb) * 0.0702702703;
    gl_FragColor = vec4(s, 1.0);
}
