// Cinders of Chaos: map shader (game_visualfx, Options > Graphics "Vignette and colour grade"). One texture read per pixel:
// a little less colour, cool shadows and warm highlights, a touch more contrast, and the edges of the picture sink into the
// dark (the vignette; strongest in the corners). Written for this server; vertex stage chaos_map_vertex.frag.
// Area mood (O234, base patch 0153): u_Params.rgb is added to the colour, u_Params.w is added to the colour kept (saturation),
// u_Params2.x is added to the contrast factor. All 0 (a client without the patch, or an area with no mood) = the grade above.
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_Norm;
uniform vec4 u_Params;
uniform vec4 u_Params2;

void main()
{
    vec4 c = texture2D(u_Tex0, v_TexCoord);
    vec3 col = c.rgb;
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(l), clamp(0.12 - u_Params.w, 0.0, 1.0));
    col += vec3(-0.010, 0.004, 0.020) * (1.0 - l) + vec3(0.024, 0.010, -0.014) * l;
    col += u_Params.xyz;
    col = (col - 0.5) * (1.06 + u_Params2.x) + 0.5;
    float r = length(v_Norm * vec2(0.88, 0.95));
    float v = smoothstep(0.50, 1.28, r);
    col *= 1.0 - 0.44 * v;
    gl_FragColor = vec4(clamp(col, 0.0, 1.0), c.a);
}
