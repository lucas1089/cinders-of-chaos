attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Resolution;
uniform float u_Depth;
uniform float u_Time;

void main()
{
    // Original vertex position
    vec2 originalVertex = a_Vertex;
    
    // Calculate center of the sprite (assuming it's centered at 0,0)
    vec2 center = vec2(0.0, 0.0);
    
    // Vectorized direction from center to vertex
    vec2 toVertex = originalVertex - center;
    
    // Scale factors - make width wider and height smaller
    // For a fat and tiny look
    float scaleX = 1.4;  // wider
    float scaleY = 0.6;  // shorter
    
    // Apply scaling while preserving the center position
    vec2 scaledVertex = center + vec2(toVertex.x * scaleX, toVertex.y * scaleY);
    
    // Apply transformations with the scaled vertex
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(scaledVertex, 1.0)).xy, u_Depth / 16384.0, 1.0);
    
    // Pass texture coordinates unchanged
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    v_TexCoord3 = (u_TextureMatrix * vec3(u_Resolution, 1.0)).xy;
} 