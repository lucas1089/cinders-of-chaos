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
    
    // Add subtle pulsating distortion
    float pulse = sin(u_Time * 0.5) * 0.002;
    position.x += sin(u_Time * 0.7 + position.y * 0.1) * pulse;
    position.y += cos(u_Time * 0.6 + position.x * 0.1) * pulse;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Set texture coordinates with subtle distortion
    vec2 texCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    texCoord.x += sin(u_Time * 0.3 + texCoord.y * 2.0) * 0.0015;
    texCoord.y += cos(u_Time * 0.4 + texCoord.x * 2.0) * 0.0015;
    v_TexCoord = texCoord;
}