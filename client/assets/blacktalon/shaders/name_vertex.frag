// Name Shader Vertex - Standard vertex shader for name text effects
// BlackTalon MMORPG

attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;

varying vec2 v_TexCoord;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy + u_Offset, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
}
