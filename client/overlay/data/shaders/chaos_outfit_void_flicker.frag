// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Void Flicker: the outfit is eaten from its edges by the void, a ragged violet-white front crawling slowly in and out (no flicker); what is left is drained dark.
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

// 1 at the silhouette's inner edge (a neighbour `r` texels away is transparent), 0 deeper inside
float rimAt(float r)
{
    vec2 d = v_Texel * r;
    float n = min(min(texture2D(u_Tex0, v_TexCoord + vec2(d.x, 0.0)).a, texture2D(u_Tex0, v_TexCoord - vec2(d.x, 0.0)).a),
                  min(texture2D(u_Tex0, v_TexCoord + vec2(0.0, d.y)).a, texture2D(u_Tex0, v_TexCoord - vec2(0.0, d.y)).a));
    return 1.0 - n;
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
    float depth = 1.0 - 0.55 * rimAt(1.0) - 0.45 * rimAt(2.0);
    float n = valueNoise(v_Px * 0.24 + vec2(t * 0.18, -t * 0.11));
    float n2 = valueNoise(v_Px * 0.6 - vec2(t * 0.1, 0.0));
    float q = 0.65 * n + 0.35 * n2 + 0.55 * depth;
    float thr = 0.42 + 0.17 * sin(t * 0.8);
    if (q < thr)
        discard;
    float band = 1.0 - smoothstep(0.0, 0.09, q - thr);
    float l = luma(c.rgb);
    vec3 col = mix(vec3(0.04, 0.0, 0.08), vec3(0.50, 0.24, 0.72), l * 0.9) + c.rgb * 0.12;
    col = mix(col, vec3(0.62, 0.30, 0.95), band * 0.85);
    col = mix(col, vec3(0.95, 0.85, 1.0), band * band * 0.8);
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
