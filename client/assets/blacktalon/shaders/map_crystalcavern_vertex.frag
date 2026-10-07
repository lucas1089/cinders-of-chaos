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
    
    // Add subtle prismatic refraction effect to vertex positions
    float prismEffect = sin(position.x * 0.02 + u_Time * 0.3) * cos(position.y * 0.02 + u_Time * 0.2) * 1.5;
    position.x += prismEffect * 0.5;
    position.y += prismEffect * 0.3;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Set texture coordinates with prismatic distortion
    vec2 texCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    texCoord.x += sin(texCoord.y * 4.0 + u_Time * 0.5) * 0.003;
    texCoord.y += cos(texCoord.x * 4.0 + u_Time * 0.3) * 0.003;
    v_TexCoord = texCoord;
} 