// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Cinder Crown: the upper half of the outfit glows like coals under a moving heat shimmer, with a bright cinder rim on top. Season pass (server seasonpass_config.lua, shaders.xml id 26).
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
    // 1 at the top of the frame, 0 at the bottom (texture y grows downwards inside the frame)
    float up = clamp(1.0 - fract(v_Px.y / 32.0), 0.0, 1.0);
    float heat = valueNoise(vec2(v_Px.x * 0.12 + t * 0.5, v_Px.y * 0.2 - t * 2.0));
    vec3 coal = mix(vec3(0.75, 0.12, 0.02), vec3(1.0, 0.62, 0.18), heat);
    vec3 col = mix(c.rgb, c.rgb * 0.6 + coal * 0.6, smoothstep(0.35, 0.9, up) * (0.45 + 0.35 * heat));
    float e = rim();
    col = mix(col, vec3(1.0, 0.72, 0.30), e * smoothstep(0.4, 1.0, up) * (0.6 + 0.4 * sin(t * 3.0 + v_Px.x * 0.3)));
    col += vec3(0.25, 0.08, 0.0) * (0.5 + 0.5 * sin(t * 2.2)) * luma(c.rgb);
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
