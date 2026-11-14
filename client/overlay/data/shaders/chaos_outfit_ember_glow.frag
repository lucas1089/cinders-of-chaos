// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Ember Glow: coals glow from the feet up and sparks rise through the outfit, each a bright pixel with a short tail.
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
    float row = rowOf();
    float vy = row / 31.0;
    float e = rimAt(1.0);
    float heat = smoothstep(0.30, 1.0, vy + 0.22 * (valueNoise(v_Px * 0.14 + vec2(0.0, -t * 0.5)) - 0.5));
    vec3 col = c.rgb * (1.0 + heat * vec3(0.75, 0.30, 0.0));
    col = mix(col, vec3(1.0, 0.45, 0.10), e * (0.45 + 0.25 * sin(t * 1.6 + v_Px.x * 0.4)));
    float px = floor(v_Px.x);
    float sp = 0.0;
    for (int k = 0; k < 3; k++) {
        float kk = float(k);
        float w = 3.0 + kk;
        float cell = floor(px / w);
        float h = cellHash(vec2(cell, kk * 17.0));
        float tx = floor(cellHash(vec2(cell, kk * 17.0 + 5.0)) * w);
        float onCol = step(abs(px - cell * w - tx), 0.5) * step(0.30, h);
        float life = fract(t * (0.20 + 0.14 * h) + h * 9.0 + kk * 0.31);
        float yy = floor(31.0 * (1.0 - life));
        float d = row - yy;
        float head = step(abs(d), 0.5);
        float tail = step(0.5, d) * step(d, 2.5) * 0.45;
        sp = max(sp, onCol * (head + tail) * (1.0 - life * 0.7));
    }
    col = mix(col, vec3(1.0, 0.82, 0.30), clamp(sp, 0.0, 1.0));
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
