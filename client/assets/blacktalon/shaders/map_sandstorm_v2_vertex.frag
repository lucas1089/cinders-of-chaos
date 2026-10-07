attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;

varying vec2 v_TexCoord;
varying vec2 v_WorldPos;

uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;

uniform float u_Time;

void main()
{
    vec3 position = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    v_WorldPos = position.xy;

    // Subtle wind-blown vertex sway (inherited from map_sandstorm) — the gentle
    // "screen wobble" of a heat haze. Kept very light so it doesn't overpower.
    float windEffect = sin(u_Time * 1.5 + position.x * 0.02) * 0.0005;
    position.y += windEffect * position.y;

    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);

    // Slight texcoord distortion that reinforces the heat-wave wobble.
    vec2 texCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    texCoord.x += sin(u_Time * 0.8 + texCoord.y * 5.0) * 0.0008;
    v_TexCoord = texCoord;
}
