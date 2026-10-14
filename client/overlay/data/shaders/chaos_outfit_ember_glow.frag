// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Ember Glow: a smouldering orange rim that flickers, warm light from below and sparks drifting up.
// Vertex stage chaos_outfit_vertex.frag.
uniform mat4 u_Color;
uniform sampler2D u_Tex0;
uniform float u_Time;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_Px;
varying vec2 v_Texel;

// the outfit with its four colours (head, body, legs, feet) from the template layer
vec4 dressed()
{
    vec4 c = texture2D(u_Tex0, v_TexCoord);
    vec4 m = texture2D(u_Tex0, v_TexCoord2);
    if (m.r > 0.9) {
        c *= m.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if (m.g > 0.9) {
        c *= u_Color[2];
    } else if (m.b > 0.9) {
        c *= u_Color[3];
    }
    return c;
}

// 1 at the silhouette's inner edge (a neighbour is transparent), 0 deeper inside
float rim()
{
    float n = min(min(texture2D(u_Tex0, v_TexCoord + vec2(v_Texel.x, 0.0)).a, texture2D(u_Tex0, v_TexCoord - vec2(v_Texel.x, 0.0)).a),
                  min(texture2D(u_Tex0, v_TexCoord + vec2(0.0, v_Texel.y)).a, texture2D(u_Tex0, v_TexCoord - vec2(0.0, v_Texel.y)).a));
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

void main()
{
    vec4 c = dressed();
    if (c.a < 0.01)
        discard;
    float t = u_Time;
    float flick = valueNoise(v_Px * 0.18 + vec2(0.0, t * 2.4));
    float e = rim();
    vec3 ember = mix(vec3(1.0, 0.32, 0.05), vec3(1.0, 0.78, 0.25), flick);
    // warm from the feet up (texture y grows downwards inside the frame; the noise breaks the gradient)
    float warm = 0.18 + 0.22 * valueNoise(v_Px * 0.07 + vec2(t * 0.3, t * 0.9));
    vec3 col = c.rgb * (1.0 + warm * vec3(0.55, 0.22, 0.0));
    col = mix(col, ember, e * (0.55 + 0.45 * flick));
    float spark = valueNoise(vec2(v_Px.x * 0.9, v_Px.y * 0.35 + t * 6.0));
    col += vec3(1.0, 0.65, 0.2) * smoothstep(0.93, 0.99, spark) * 0.9;
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
