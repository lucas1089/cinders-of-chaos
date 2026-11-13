// Cinders of Chaos: HD minimap shader (base patch 0197, module game_minimaphd). The client composes each 64 x 64 tile block of the
// explored map from the item swatches (shadows, rim and tint are baked in) and draws it with this program, which only moves the
// water and the lava. The picture tells the liquids by its alpha: 255 plain, 245 water, 235 lava, 0 not explored; a linear
// filter between two tiles gives a value between, which reads as a weaker effect (chaosminimaphd.h liquidWeights is the same
// rule, held by the header test). Output alpha is 1 for every explored pixel; the explored edge keeps its soft fade.
// The waves are anchored to the world: u_Params.xy is the tile of the block's corner modulo 256, u_Params.z the zoom in px per
// tile, and every wave number is a whole number of cycles over 256 tiles, so a wave runs on over the seam between two blocks.
// Written for this server; vertex stage chaos_minimap_vertex.frag.
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Params;
varying vec2 v_TexCoord;

void main()
{
    vec4 c = texture2D(u_Tex0, v_TexCoord);
    float a = c.a;
    float d = 1.0 - a;
    float live = step(0.88, a);
    float lava = clamp((d - 0.04) / 0.04, 0.0, 1.0) * live;
    float water = clamp(d / 0.04, 0.0, 1.0) * (1.0 - clamp((d - 0.04) / 0.04, 0.0, 1.0)) * live;
    vec2 tile = u_Params.xy + v_TexCoord * 64.0;
    float k = 6.2831853 / 256.0;
    float t = u_Time;
    float wave = sin(t * 2.1 + tile.x * k * 18.0 + tile.y * k * 28.0) * sin(t * 1.4 - tile.x * k * 22.0 + tile.y * k * 12.0);
    c.rgb *= 1.0 + water * 0.07 * wave;
    float spark = sin(t * 2.5 + tile.x * k * 46.0 + tile.y * k * 32.0) + sin(t * 3.4 + tile.x * k * 24.0 - tile.y * k * 58.0);
    c.rgb += vec3(water * step(1.8, spark) * step(3.0, u_Params.z) * 0.15);
    float pulse = 0.5 + 0.5 * sin(t * 3.1 + tile.x * k * 8.0 + tile.y * k * 4.0);
    c.rgb *= 1.0 + lava * 0.18 * pulse;
    c.rgb += lava * pulse * vec3(0.05, 0.015, 0.0);
    gl_FragColor = vec4(clamp(c.rgb, 0.0, 1.0), clamp(a / 0.9, 0.0, 1.0));
}
