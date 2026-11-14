// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Frost Rime: a rime of ice crystals creeps up from the feet and melts back in a slow cycle; the frozen part is faceted with a bright front and glints.
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
    float vy = rowOf() / 31.0;
    float up = 1.0 - vy;
    float l = luma(c.rgb);
    float level = 0.38 + 0.30 * sin(t * 0.55);
    vec2 cell = floor(v_Px / 3.0);
    float seed = cellHash(cell);
    float front = level + (seed - 0.5) * 0.22 + (valueNoise(v_Px * 0.2) - 0.5) * 0.10;
    float ice = 1.0 - smoothstep(front - 0.015, front + 0.015, up);
    float edge = 1.0 - smoothstep(0.0, 0.07, abs(up - front));
    vec3 cool = mix(c.rgb, vec3(0.30, 0.52, 0.82) * (0.55 + l), 0.30);
    vec3 facet = mix(vec3(0.45, 0.70, 0.95), vec3(0.93, 0.98, 1.0), 0.25 + 0.75 * seed) * (0.65 + 0.45 * l);
    vec3 col = mix(cool, facet, ice * 0.88);
    col = mix(col, vec3(0.95, 1.0, 1.0), edge * 0.8);
    float glint = pow(max(0.0, sin(t * 1.8 + seed * 40.0)), 30.0) * step(0.80, seed) * ice;
    col += vec3(0.9, 0.97, 1.0) * glint;
    col = mix(col, vec3(0.85, 0.95, 1.0), rimAt(1.0) * 0.45);
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
