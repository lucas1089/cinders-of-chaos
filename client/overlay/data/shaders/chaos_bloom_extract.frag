// Cinders of Chaos: bright pass of the soft glow (game_visualfx, Options > Graphics "Soft glow"; base patch 0132).
// Drawn once per frame into a buffer a quarter of the map's size. Four taps average the map picture over the area of each small
// pixel; a tap keeps its colour only when it is bright AND stands out from the ground round it:
//  - luma: from 0.80 to 0.96 (smoothstep), black under 0.80, so a green swamp or a brown cave floor never feeds the glow;
//  - contrast (O210, seen in a client 2026-11-26): the tap's luma above the mean luma of a ring of 8 reads about 24 picture
//    pixels away (12 tap offsets, three quarters of a tile), from 0.15 to 0.35 (smoothstep);
//  - bright ground: the ring's mean luma from 0.50 to 0.70 turns the tap off (1 - smoothstep).
// Before the contrast rule a snow field or white sand (a third of the map picture over 0.80) fed the glow everywhere and the
// whole field went pale (mean +3.9 of 255 by day, the ice's own blue washed out). Now a field is its own surroundings and gives
// nothing; a spell burst, an energy bolt or a bright missile over darker ground is far brighter than its ring and still glows.
// The colour stays the source's own. The picture read is the map before the light map (the engine draws the light after the
// glow), so a bright sprite glows by its own colours and the light then darkens it with the rest of the place.
// u_Params.xy: half a small pixel in the map picture's texture coordinates (the tap offset).
uniform sampler2D u_Tex0;
uniform vec4 u_Params;
varying vec2 v_TexCoord;

const vec3 Y = vec3(0.299, 0.587, 0.114);

float luma(vec2 uv)
{
    return dot(texture2D(u_Tex0, uv).rgb, Y);
}

vec3 bright(vec2 uv, float ground)
{
    vec3 c = texture2D(u_Tex0, uv).rgb;
    float l = dot(c, Y);
    return c * smoothstep(0.80, 0.96, l) * smoothstep(0.15, 0.35, l - ground);
}

void main()
{
    vec2 o = u_Params.xy;
    vec2 r = o * 12.0;
    vec2 d = o * 8.5;
    float ground = (luma(v_TexCoord + vec2(r.x, 0.0)) + luma(v_TexCoord - vec2(r.x, 0.0))
                  + luma(v_TexCoord + vec2(0.0, r.y)) + luma(v_TexCoord - vec2(0.0, r.y))
                  + luma(v_TexCoord + d) + luma(v_TexCoord - d)
                  + luma(v_TexCoord + vec2(d.x, -d.y)) + luma(v_TexCoord + vec2(-d.x, d.y))) * 0.125;
    vec3 s = bright(v_TexCoord + vec2(-o.x, -o.y), ground) + bright(v_TexCoord + vec2(o.x, -o.y), ground)
           + bright(v_TexCoord + vec2(-o.x, o.y), ground) + bright(v_TexCoord + vec2(o.x, o.y), ground);
    gl_FragColor = vec4(s * (0.25 * (1.0 - smoothstep(0.50, 0.70, ground))), 1.0);
}
