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
    // Calculate position
    vec3 position = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Pass world position to fragment shader for effect calculation
    v_WorldPos = position.xy;
    
    // Add heat distortion effect to vertex positions
    float heatWave = sin(position.y * 0.05 + u_Time * 1.5) * sin(position.x * 0.04 + u_Time) * 1.0;
    position.x += heatWave;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Apply heat distortion to texture coordinates as well
    vec2 texCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    texCoord.x += sin(texCoord.y * 10.0 + u_Time * 2.0) * 0.002;
    v_TexCoord = texCoord;
} 