attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_Center;
varying float v_DistanceFromCenter;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;
uniform float u_Time;

// Parameters for ring effect
float flowSpeed = 1.5;
float waveFrequency = 3.5;

vec2 effectTextureSize = vec2(609.0, 559.0);
vec2 direction = vec2(0.0, 1.0);  // Upward movement
float speed = 10.0;
float angle = 30.0;

vec2 rotate(vec2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    mat2 m = mat2(c, -s, s, c);
    return m * v;
}

void main()
{
    vec3 pos = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    gl_Position = vec4((u_ProjectionMatrix * pos).xy, 1.0, 1.0);
    
    // Calculate center point and distance for rings
    vec2 spriteCenter = floor(pos.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    vec2 fromCenter = pos.xy - spriteCenter;
    v_Center = fromCenter / 48.0; // Normalize
    v_DistanceFromCenter = length(v_Center);
    
    // Basic texture coordinates
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Effect texture coordinates
    vec2 offset = direction * speed * u_Time;
    v_TexCoord3 = ((a_TexCoord + rotate(direction, (angle / 180.0) * 3.14) * u_Time * speed) / effectTextureSize);
    
    // Add wave effect to the coordinates
    float wave = sin(v_TexCoord3.y * 10.0 + u_Time * 2.0) * 0.02;
    v_TexCoord3.x += wave;
} 