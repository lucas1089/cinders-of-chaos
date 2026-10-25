// Cinders of Chaos: bright pass of the soft glow (game_visualfx, Options > Graphics "Soft glow"; base patch 0132).
// Drawn once per frame into a buffer a quarter of the map's size. Four taps average the map picture over the area of each small
// pixel; a tap keeps its colour only as its luma climbs from 0.80 to 0.96 (smoothstep) and is black under 0.80. So a green swamp,
// a brown cave floor or any ordinary sprite gives black here and nothing of it reaches the glow; only very bright light does
// (spell effects, missiles, fire, lava, the engine's light sources at full strength). The colour stays the source's own.
// u_Params.xy: half a small pixel in the map picture's texture coordinates (the tap offset).
uniform sampler2D u_Tex0;
uniform vec4 u_Params;
varying vec2 v_TexCoord;

vec3 bright(vec2 uv)
{
    vec3 c = texture2D(u_Tex0, uv).rgb;
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    return c * smoothstep(0.80, 0.96, l);
}

void main()
{
    vec2 o = u_Params.xy;
    vec3 s = bright(v_TexCoord + vec2(-o.x, -o.y)) + bright(v_TexCoord + vec2(o.x, -o.y))
           + bright(v_TexCoord + vec2(-o.x, o.y)) + bright(v_TexCoord + vec2(o.x, o.y));
    gl_FragColor = vec4(s * 0.25, 1.0);
}
