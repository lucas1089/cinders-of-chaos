// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Blood Pulse: a heartbeat (two beats, a rest) floods the body red and lights veins under the skin.
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
    float ph = fract(t / 1.15);
    // pow() of a negative base is undefined in GLSL: square by hand
    float b1 = (ph - 0.08) / 0.05;
    float b2 = (ph - 0.26) / 0.05;
    float beat = exp(-b1 * b1) + 0.7 * exp(-b2 * b2);
    vec3 blood = vec3(0.75, 0.04, 0.06);
    vec3 col = mix(c.rgb, c.rgb * vec3(1.0, 0.45, 0.45) + blood * 0.35, 0.35 + 0.4 * beat);
    // veins: thin ridges of a slow noise
    float n = valueNoise(v_Px * 0.16 + vec2(0.0, t * 0.1));
    float vein = smoothstep(0.06, 0.0, abs(n - 0.5));
    col = mix(col, vec3(1.0, 0.15, 0.12), vein * (0.25 + 0.6 * beat));
    float e = rim();
    col = mix(col, vec3(0.9, 0.08, 0.1), e * 0.5 * beat);
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
