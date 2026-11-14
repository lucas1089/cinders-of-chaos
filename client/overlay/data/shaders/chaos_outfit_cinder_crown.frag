// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Cinder Crown: lava cracks glow through a charred outfit, thickest over the head and shoulders, with heat shimmer rising and a bright ember crown along the top.
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
    float t = u_Time;
    float row = rowOf();
    float up = 1.0 - row / 31.0;
    float shimmer = sin(v_Px.y * 0.6 - t * 3.0) * v_Texel.x * 0.9 * up;
    vec4 c = dressedAt(vec2(shimmer, 0.0));
    if (c.a < 0.01)
        discard;
    vec3 charred = mix(c.rgb, vec3(0.10, 0.05, 0.04) + c.rgb * 0.35, 0.40 * (0.4 + 0.6 * up));
    // cracks: the gap between the nearest and the second nearest of a drifting point per 7 px cell
    vec2 p = v_Px / 7.0;
    vec2 ip = floor(p);
    float f1 = 9.0;
    float f2 = 9.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = ip + vec2(float(i), float(j));
            vec2 o = vec2(cellHash(g), cellHash(g + 7.3));
            vec2 pt = g + 0.5 + 0.38 * sin(t * 0.35 + 6.2831 * o);
            float d = length(p - pt);
            if (d < f1) {
                f2 = f1;
                f1 = d;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    float crack = 1.0 - smoothstep(0.05, 0.20, f2 - f1);
    float strength = (0.35 + 0.65 * smoothstep(0.15, 0.9, up)) * (0.75 + 0.25 * sin(t * 1.4 + p.x));
    vec3 lava = mix(vec3(0.85, 0.16, 0.03), vec3(1.0, 0.78, 0.25), crack * crack);
    vec3 col = mix(charred, lava, crack * strength);
    float e = rimAt(1.0);
    float crown = smoothstep(0.68, 0.95, up) * e;
    col = mix(col, vec3(1.0, 0.72, 0.28), crown * (0.65 + 0.25 * sin(t * 2.0 + v_Px.x * 0.5)));
    col += vec3(0.10, 0.03, 0.0) * up;
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
