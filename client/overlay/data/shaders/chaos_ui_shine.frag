// Cinders of Chaos: a light sweep across a rarity frame (legendary and up, uniques; game_shaderfx). The frame keeps
// its own picture and image-color; a slanted band of light crosses it every period, then the frame rests.
// u_Params: x = phase offset in seconds (frames side by side do not sweep together), y = period in seconds (0 = 3.5),
// z = strength 0..1 (0 = 0.8), w = band width (0 = 0.12).
uniform sampler2D u_Tex0;
uniform vec4 u_Color;
uniform vec4 u_Params;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec4 base = texture2D(u_Tex0, v_TexCoord) * u_Color;
    if (base.a < 0.01)
        discard;
    float period = u_Params.y > 0.0 ? u_Params.y : 3.5;
    float strength = u_Params.z > 0.0 ? u_Params.z : 0.8;
    float width = u_Params.w > 0.0 ? u_Params.w : 0.12;
    float cycle = fract((u_Time + u_Params.x) / period);
    // the sweep uses the first 45% of the period, from beyond the top left to beyond the bottom right
    float sweep = clamp(cycle / 0.45, 0.0, 1.0);
    float pos = mix(-0.4, 1.6, sweep);
    float along = v_TexCoord.x * 0.75 + v_TexCoord.y * 0.6;
    float d = (along - pos) / width;
    float band = exp(-d * d) * step(cycle, 0.45);
    float trail = exp(-(d + 1.8) * (d + 1.8) * 2.0) * 0.4 * step(cycle, 0.45);
    float light = (band + trail) * strength;
    vec3 col = base.rgb + (vec3(1.0) - base.rgb) * light + base.rgb * light * 0.5;
    gl_FragColor = vec4(min(col, vec3(1.0)), base.a);
}
