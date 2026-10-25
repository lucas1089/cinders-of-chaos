// Cinders of Chaos: water ground shader (game_visualfx option "Living water and lava", base patch 0128). A gentle ripple of
// at most one texture pixel and a brightness wave of a few percent; colour and alpha are the sprite's own, so every biome keeps
// its water. The ripple fades to nothing at the tile edge (a sprite never reads the pixels of the next frame in the sheet) and
// the phases are whole multiples of pi across the tile, so the waves run on over the seam between two tiles.
// Written for this server; vertex stage chaos_liquid_vertex.frag.
uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;
varying vec2 v_Norm;
varying vec2 v_Texel;

void main()
{
    vec2 edge = clamp((1.0 - abs(v_Norm)) * 8.0, 0.0, 1.0);
    float w = edge.x * edge.y;
    float t = u_Time;
    vec2 ph = 3.14159 * v_Norm;
    vec2 d = vec2(sin(t * 1.3 + ph.x + 2.0 * ph.y), cos(t * 1.1 + 2.0 * ph.x - ph.y)) * v_Texel * w;
    vec4 c = texture2D(u_Tex0, v_TexCoord + d);
    float glint = sin(t * 0.9 + ph.x + ph.y);
    c.rgb *= 1.0 + 0.035 * glint;
    gl_FragColor = vec4(clamp(c.rgb, 0.0, 1.0), c.a);
}
