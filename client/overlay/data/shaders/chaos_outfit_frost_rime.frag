// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Frost Rime: the colours cool to ice, a white-blue rime along the edges and crystals that glint.
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
    float l = luma(c.rgb);
    vec3 ice = mix(vec3(0.20, 0.38, 0.62), vec3(0.85, 0.95, 1.0), l);
    vec3 col = mix(c.rgb, ice, 0.55);
    float e = rim();
    col = mix(col, vec3(0.88, 0.97, 1.0), e * 0.75);
    // crystals: fixed cells that glint one after another
    vec2 cell = floor(v_Px / 3.0);
    float seed = cellHash(cell);
    float glint = pow(max(0.0, sin(t * 2.0 + seed * 40.0)), 24.0) * step(0.82, seed);
    col += vec3(0.9, 0.97, 1.0) * glint * 0.85;
    // frost creeping in a slow noise
    float frost = smoothstep(0.55, 0.85, valueNoise(v_Px * 0.22 + vec2(t * 0.05, 0.0)));
    col = mix(col, vec3(0.92, 0.97, 1.0), frost * 0.25);
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
