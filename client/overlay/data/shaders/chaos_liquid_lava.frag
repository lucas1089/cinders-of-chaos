// Cinders of Chaos: lava ground shader (game_visualfx option "Living water and lava", base patch 0128). Slower and thicker
// than the water: a ripple of at most one texture pixel and a brightness wave of about 12% that makes the lava seem to
// breathe. Only the brightness changes (colour ratios and alpha stay the sprite's own), so the lava of every biome keeps its
// hue. The ripple fades to nothing at the tile edge and the phases are whole multiples of pi across the tile, so the waves run
// on over the seam between two tiles. Written for this server; vertex stage chaos_liquid_vertex.frag.
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
    vec2 d = vec2(sin(t * 0.8 + ph.x + ph.y), cos(t * 0.7 + ph.x - 2.0 * ph.y)) * v_Texel * w;
    vec4 c = texture2D(u_Tex0, v_TexCoord + d);
    float swell = 0.5 + 0.5 * sin(t * 1.2 + ph.x + 2.0 * ph.y);
    c.rgb *= 0.94 + 0.18 * swell;
    gl_FragColor = vec4(clamp(c.rgb, 0.0, 1.0), c.a);
}
