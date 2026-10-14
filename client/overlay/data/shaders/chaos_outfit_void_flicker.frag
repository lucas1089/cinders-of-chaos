// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Void Flicker: the body sinks into violet dark, its edge flickers, now and then a band of it drops out.
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
    vec3 col = mix(vec3(0.03, 0.0, 0.06), vec3(0.42, 0.18, 0.62), l * 0.9) + c.rgb * 0.18;
    float flick = step(0.35, valueNoise(vec2(t * 9.0, 3.1)));
    float e = rim();
    col = mix(col, vec3(0.72, 0.38, 1.0), e * (0.35 + 0.65 * flick));
    // a horizontal band that thins out for a moment (a few times a second, at a random height)
    float slot = floor(t * 3.0);
    float bandY = cellHash(vec2(slot, 7.0)) * 64.0;
    float band = smoothstep(2.5, 0.0, abs(mod(v_Px.y, 64.0) - bandY)) * step(0.6, cellHash(vec2(slot, 1.0)));
    float specks = step(0.9, valueNoise(v_Px * 0.6 + vec2(t * 4.0, -t * 3.0)));
    float a = c.a * (1.0 - 0.75 * band) * (1.0 - 0.5 * specks);
    gl_FragColor = vec4(col, a);
}
