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
vec2 direction1 = vec2(0.3, 0.5);
vec2 direction2 = vec2(-0.4, -0.3);
float speed1 = 5.0;
float speed2 = 7.0;
float angle1 = 35.0;
float angle2 = -65.0;

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
    
    // Calculate angles in radians
    float angleRad1 = (angle1 / 180.0) * 3.14;
    float angleRad2 = (angle2 / 180.0) * 3.14;
    
    // Add some stepped/quantized movement for a more crystalline feel
    float stepTime1 = floor(u_Time * 2.0) / 2.0; // Step every 0.5 seconds
    float stepTime2 = floor(u_Time * 3.0) / 3.0; // Step every 0.33 seconds
    
    // Add occasional "cracks" or shifts in the texture coordinates
    float crackEffect1 = step(0.95, sin(u_Time * 0.2) * 0.5 + 0.5) * sin(a_TexCoord.y * 30.0) * 0.05;
    float crackEffect2 = step(0.95, cos(u_Time * 0.3) * 0.5 + 0.5) * sin(a_TexCoord.x * 25.0) * 0.05;
    
    // Set texture coordinates with different directions, speeds and effects
    v_TexCoord3 = ((a_TexCoord + crackEffect1 + 
                    rotate(direction1, angleRad1) * stepTime1 * speed1) / effectTextureSize);
    
    v_TexCoord4 = ((a_TexCoord + crackEffect2 + 
                    rotate(direction2, angleRad2) * stepTime2 * speed2) / effectTextureSize);
    
    // Pass vertex color through
    v_Color = vec4(1.0, 1.0, 1.0, 1.0);
} 