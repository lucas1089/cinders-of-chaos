// Cinders of Chaos: map shader (game_visualfx, Options > Graphics "Vignette and colour grade"). One texture read per pixel:
// a little less colour, cool shadows and warm highlights, a touch more contrast, and the edges of the picture sink into the
// dark (the vignette; strongest in the corners). Written for this server; vertex stage chaos_map_vertex.frag.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_Norm;

void main()
{
    vec4 c = texture2D(u_Tex0, v_TexCoord);
    vec3 col = c.rgb;
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(l), 0.12);
    col += vec3(-0.010, 0.004, 0.020) * (1.0 - l) + vec3(0.024, 0.010, -0.014) * l;
    col = (col - 0.5) * 1.06 + 0.5;
    float r = length(v_Norm * vec2(0.88, 0.95));
    float v = smoothstep(0.50, 1.28, r);
    col *= 1.0 - 0.44 * v;
    gl_FragColor = vec4(clamp(col, 0.0, 1.0), c.a);
}
