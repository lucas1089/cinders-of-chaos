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
    
    // Pass world position to fragment shader
    v_WorldPos = position.xy;
    
    // Add subtle trembling effect
    float trembleX = sin(u_Time * 3.0) * 0.001 * sin(u_Time * 5.0 + position.y * 0.1);
    float trembleY = cos(u_Time * 2.7) * 0.001 * cos(u_Time * 4.5 + position.x * 0.1);
    
    position.x += trembleX;
    position.y += trembleY;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Set texture coordinates
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
} 