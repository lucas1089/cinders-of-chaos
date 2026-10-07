attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;

varying vec2 v_TexCoord;
varying vec2 v_Position;

void main()
{
    vec3 pos = u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex - u_Offset, 1.0);
    gl_Position = vec4(pos.xy, 0.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_Position = gl_Position.xy;
} 