// Cinders of Chaos outfit shader (game_visualfx, base patch 0126 Creature:flashHit): the hit flash, the whole outfit turned
// red for a few frames. Vertex stage chaos_outfit_vertex.frag. Written for this server.
uniform mat4 u_Color;
uniform sampler2D u_Tex0;
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

void main()
{
    vec4 c = dressed();
    if (c.a < 0.01)
        discard;
    float l = dot(c.rgb, vec3(0.30, 0.58, 0.12));
    // the flash keeps a trace of the sprite's own shading, so the shape stays readable
    vec3 col = mix(c.rgb, vec3(1.0, 0.16, 0.12) * (0.80 + 0.35 * l), 0.62);
    gl_FragColor = vec4(min(col, vec3(1.0)), c.a);
}
