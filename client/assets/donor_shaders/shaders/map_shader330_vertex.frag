attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform float u_Time;

varying vec2 v_TexCoord;
varying vec2 v_FragCoord;
varying float v_Time;

void main()
{
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex, 1.0)).xy, 0.0, 1.0);
    v_FragCoord = gl_Position.xy;
    v_Time = u_Time;
} 