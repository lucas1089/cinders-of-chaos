uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    float reduction = -0.9;

    vec4 col = texture2D(u_Tex0, v_TexCoord);
    float luminance = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    if (luminance > 0.9) {
        col.rgb = mix(col.rgb, vec3(1.0), reduction);
    }
    col.rgb = clamp(col.rgb, 0.0, 1.0);
    gl_FragColor = col;
}
