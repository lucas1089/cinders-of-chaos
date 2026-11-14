// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Spectral Ghost: a cold translucent ectoplasm, clearer toward the edges, with a rune contour that scans in from the edge. It reads only the sprite alpha and the time, so tall outfits drawn as several tiles have no seam.
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

// how many pixels the silhouette's edge is away: 1 at the edge, up to 5 deep inside. It reads only the sprite's own
// alpha, so it is the same on every 32 px tile of a tall outfit (the engine draws them as separate quads: a row or
// a position in the atlas says nothing about where the tile sits in the figure)
float edgeDepth()
{
    return 5.0 - (rimAt(1.0) + rimAt(2.0) + rimAt(3.0) + rimAt(4.0));
}

void main()
{
    vec4 c = dressedAt(vec2(0.0));
    if (c.a < 0.01)
        discard;
    float t = u_Time;
    float l = luma(c.rgb);
    float depth = edgeDepth();
    vec3 col = mix(vec3(0.38, 0.70, 0.78), vec3(0.88, 1.0, 1.0), l);
    float inner = clamp((depth - 1.0) / 4.0, 0.0, 1.0);
    float step_ = floor(fract(t * 0.45) * 7.0) + 1.0;
    float lit = 1.0 - smoothstep(0.0, 0.7, abs(depth - step_));
    float dash = step(0.5, fract(floor(v_Px.x + v_Px.y) * 0.25 + floor(t * 2.0) * 0.5));
    float rune = lit * (0.45 + 0.55 * dash);
    float breathe = 0.5 + 0.5 * sin(t * 2.0);
    col = mix(col, vec3(0.80, 1.0, 1.0), (1.0 - inner) * 0.55);
    col += vec3(0.35, 0.75, 0.80) * rune;
    float a = c.a * min(1.0, 0.42 + 0.14 * breathe + 0.22 * l + 0.28 * (1.0 - inner) + rune * 0.3);
    gl_FragColor = vec4(min(col, vec3(1.0)), a);
}
