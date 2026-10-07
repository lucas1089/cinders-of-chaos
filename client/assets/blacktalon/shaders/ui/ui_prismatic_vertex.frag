// UI Prismatic - vertex
// Standard UI image vertex. v_TexCoord is normalized (0..1 across the image) by
// u_TextureMatrix, which the fragment uses both to sample and to lay the rainbow.
attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;

varying vec2 v_TexCoord;

void main()
{
    vec3 pos = u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex - u_Offset, 1.0);
    gl_Position = vec4(pos.xy, 0.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
}
