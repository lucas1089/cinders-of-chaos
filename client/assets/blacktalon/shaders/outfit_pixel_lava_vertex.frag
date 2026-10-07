attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
varying vec4 v_Color;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;
uniform float u_Time;

vec2 effectTextureSize = vec2(609.0, 559.0);
vec2 direction1 = vec2(0.5, 0.3);
vec2 direction2 = vec2(-0.2, 0.6);
float speed1 = 6.0;
float speed2 = 4.5;
float angle1 = 50.0;
float angle2 = -30.0;

vec2 rotate(vec2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    mat2 m = mat2(c, -s, s, c);
    return m * v;
}

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord,1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset,1.0)).xy;
    
    // Create opposing directional flows for the two textures to enhance the "battle" effect
    float angleRad1 = (angle1 / 180.0) * 3.14;
    float angleRad2 = (angle2 / 180.0) * 3.14;
    
    // Add some oscillation to the texture coordinates for more dynamic movement
    vec2 flowOffset1 = direction1 * sin(u_Time * 0.3) * 0.1;
    vec2 flowOffset2 = direction2 * cos(u_Time * 0.4) * 0.1;
    
    // Set texture coordinates with different directions and speeds
    v_TexCoord3 = ((a_TexCoord + rotate(direction1 + flowOffset1, angleRad1) * u_Time * speed1) / effectTextureSize);
    v_TexCoord4 = ((a_TexCoord + rotate(direction2 + flowOffset2, angleRad2) * u_Time * speed2) / effectTextureSize);
    
    // Pass vertex color through
    v_Color = vec4(1.0, 1.0, 1.0, 1.0);
} 