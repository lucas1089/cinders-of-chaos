varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_var0; // saturation: 0.0 = grayscale, 1.0 = full color

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    vec3 grayscale = vec3(gray);
    color.rgb = mix(grayscale, color.rgb, u_var0);
    gl_FragColor = color;
}
