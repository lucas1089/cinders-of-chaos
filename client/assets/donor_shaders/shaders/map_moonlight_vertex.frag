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
    
    // Add subtle pulsating effect for moonlight glow
    float pulse = sin(u_Time * 0.2) * 0.001;
    position.x += sin(position.y * 0.01 + u_Time * 0.1) * pulse;
    position.y += cos(position.x * 0.01 + u_Time * 0.1) * pulse;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Set texture coordinates
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
} 