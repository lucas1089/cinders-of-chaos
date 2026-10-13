// Cinders of Chaos: greyscale for locked or unusable slots and items (game_shaderfx). Works as a widget image shader
// and as an item shader (UIItem:setItemShader): luminance, a little darker, the alpha kept.
uniform sampler2D u_Tex0;
uniform vec4 u_Color;
varying vec2 v_TexCoord;

void main()
{
    vec4 c = texture2D(u_Tex0, v_TexCoord);
    if (c.a < 0.01)
        discard;
    float l = dot(c.rgb, vec3(0.30, 0.58, 0.12));
    l = l * 0.72 + 0.04;
    gl_FragColor = vec4(vec3(l), c.a) * vec4(vec3(1.0), u_Color.a);
}
