// Cinders of Chaos outfit shader (game_chaosshaders, written for this server). Ash Drift: the outfit greys toward ash, a pale cinder rim breathes slowly and grey flakes drift down across it. Season pass (server seasonpass_config.lua, shaders.xml id 25).
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
    // half way to grey ash, a little warmth kept in the dark parts
    vec3 col = mix(c.rgb, vec3(l * 0.92, l * 0.88, l * 0.84), 0.5);
    float breath = 0.5 + 0.5 * sin(t * 1.6);
    float e = rim();
    col = mix(col, vec3(0.86, 0.80, 0.72), e * (0.35 + 0.30 * breath));
    // flakes falling: a sparse noise field moving downwards (texture y grows downwards inside the frame)
    float flake = valueNoise(vec2(v_Px.x * 0.6 + sin(t * 0.7) * 2.0, v_Px.y * 0.6 - t * 3.5));
    col = mix(col, vec3(0.78, 0.76, 0.74), smoothstep(0.90, 0.97, flake) * 0.75);
    float ember = valueNoise(v_Px * 0.25 + vec2(t * 0.4, -t * 1.1));
    col += vec3(0.9, 0.35, 0.08) * smoothstep(0.95, 0.995, ember) * 0.8;
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
