uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    float contrast = 1.4;

    vec4 col = texture2D(u_Tex0, v_TexCoord);
    col.rgb = 0.5 + (col.rgb - 0.5) * contrast;
    col.rgb = clamp(col.rgb, 0.0, 1.0);
    gl_FragColor = col;
}
