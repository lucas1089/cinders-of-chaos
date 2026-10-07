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
    
    // Pass world position to fragment shader for sandstorm calculation
    v_WorldPos = position.xy;
    
    // Add subtle vertex distortion for wind-blown effect
    float windEffect = sin(u_Time * 1.5 + position.x * 0.02) * 0.001;
    position.y += windEffect * position.y;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Set texture coordinates with slight distortion
    vec2 texCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    texCoord.x += sin(u_Time * 0.8 + texCoord.y * 5.0) * 0.002;
    v_TexCoord = texCoord;
} 