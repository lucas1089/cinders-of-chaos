attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;
uniform float u_Time;

varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_Position;
varying float v_Time;

vec2 effectTextureSize = vec2(609.0, 559.0);
vec2 direction = vec2(0.0, -0.6);  // Upward floating particles
float speed = 4.0;
float angle = 15.0;

vec2 rotate(vec2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    mat2 m = mat2(c, -s, s, c);
    return m * v;
}

void main()
{
    vec3 pos = u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex - u_Offset, 1.0);
    gl_Position = vec4(pos.xy, 0.0, 1.0);
    
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Add floating movement for particles
    v_TexCoord3 = ((a_TexCoord + rotate(direction, (angle / 180.0) * 3.14) * u_Time * speed) / effectTextureSize);
    
    v_Position = gl_Position.xy;
    v_Time = u_Time;
} 