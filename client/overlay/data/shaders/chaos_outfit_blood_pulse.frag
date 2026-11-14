// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Heartblood: a double heartbeat sends a red wave out from the chest, dark veins glow with each beat, the outfit warms and darkens between beats.
// Vertex stage chaos_outfit_vertex.frag.
uniform mat4 u_Color;
uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_Px;
varying vec2 v_Texel;

// the outfit with its four colours (head, body, legs, feet) from the template layer, read at a shift in texture
// coordinates (a shader that wobbles the picture passes one)
vec4 dressedAt(vec2 sh)
{
    vec4 c = texture2D(u_Tex0, v_TexCoord + sh);
    vec4 m = texture2D(u_Tex0, v_TexCoord2 + sh);
    if (m.r > 0.9) {
        c *= m.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if (m.g > 0.9) {
        c *= u_Color[2];
    } else if (m.b > 0.9) {
        c *= u_Color[3];
    }
    return c;
}

// 1 at the silhouette's inner edge (a neighbour `r` texels away is transparent), 0 deeper inside. A neighbour outside
// this 32 px tile counts as opaque: the engine draws a tall outfit as separate tiles, so what lies beyond a tile's
// border in the atlas is another picture, and reading it made a false edge (a bright cross) where tiles meet.
float rimAt(float r)
{
    vec2 d = v_Texel * r;
    vec2 lp = fract(v_Px / 32.0) * 32.0;
    float aR = lp.x + r >= 32.0 ? 1.0 : texture2D(u_Tex0, v_TexCoord + vec2(d.x, 0.0)).a;
    float aL = lp.x - r < 0.0 ? 1.0 : texture2D(u_Tex0, v_TexCoord - vec2(d.x, 0.0)).a;
    float aD = lp.y + r >= 32.0 ? 1.0 : texture2D(u_Tex0, v_TexCoord + vec2(0.0, d.y)).a;
    float aU = lp.y - r < 0.0 ? 1.0 : texture2D(u_Tex0, v_TexCoord - vec2(0.0, d.y)).a;
    return 1.0 - min(min(aR, aL), min(aD, aU));
}

float cellHash(vec2 c)
{
    c = fract(c * vec2(0.2713, 0.4127) + vec2(0.11, 0.73));
    c += dot(c, c.yx + 23.17);
    return fract((c.x + 0.37) * (c.y + 0.61) * 47.3);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 s = f * f * (3.0 - 2.0 * f);
    return mix(mix(cellHash(i), cellHash(i + vec2(1.0, 0.0)), s.x),
               mix(cellHash(i + vec2(0.0, 1.0)), cellHash(i + vec2(1.0, 1.0)), s.x), s.y);
}

float luma(vec3 c)
{
    return dot(c, vec3(0.30, 0.58, 0.12));
}

// the row (0 top .. 31 bottom) of this pixel in its 32 px cell
float rowOf()
{
    return floor(fract(v_Px.y / 32.0) * 32.0);
}

void main()
{
    vec4 c = dressedAt(vec2(0.0));
    if (c.a < 0.01)
        discard;
    float t = u_Time;
    float ph = fract(t * 0.85);
    float b1 = exp(-pow((ph - 0.04) * 7.0, 2.0));
    float b2 = 0.65 * exp(-pow((ph - 0.26) * 7.0, 2.0));
    float beat = b1 + b2;
    float lx = fract(v_Px.x / 32.0) * 32.0;
    float ly = fract(v_Px.y / 32.0) * 32.0;
    float dist = length(vec2(lx - 16.0, (ly - 17.0) * 0.9));
    float wave = (1.0 - smoothstep(0.0, 3.0, abs(dist - ph * 34.0))) * (1.0 - ph);
    float l = luma(c.rgb);
    vec3 col = mix(c.rgb, vec3(0.50, 0.04, 0.05) * (0.5 + l), 0.40);
    float vein = 1.0 - smoothstep(0.0, 0.05, abs(valueNoise(v_Px * 0.27) - 0.5));
    col = mix(col, vec3(1.0, 0.12, 0.10), vein * (0.20 + 0.65 * beat));
    col += vec3(0.55, 0.06, 0.04) * wave;
    col *= 1.0 + 0.30 * beat;
    col = mix(col, vec3(0.14, 0.0, 0.02), rimAt(1.0) * 0.8);
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
