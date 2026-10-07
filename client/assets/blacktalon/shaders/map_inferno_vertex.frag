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

    // Very subtle rising-heat vertex sway. Kept tiny so it never disturbs
    // readability of the scene — the bulk of the heat shimmer is done
    // per-pixel in the fragment shader, edge-masked to keep the center clean.
    float windEffect = sin(u_Time * 1.3 + position.x * 0.02) * 0.0004;
    position.y += windEffect * position.y;

    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);

    vec2 texCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    texCoord.x += sin(u_Time * 0.7 + texCoord.y * 5.0) * 0.0006;
    v_TexCoord = texCoord;
}
