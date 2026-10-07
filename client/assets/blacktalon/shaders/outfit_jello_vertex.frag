attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform float u_Time;

// Jello parameters
float vertexWobbleSpeed = 1.5; // Speed of wobble
float vertexWobbleAmount = 0.005; // Amount of vertex movement

void main() {
    // Calculate original position
    vec3 originalPos = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Calculate time-based wobble
    float time = u_Time * vertexWobbleSpeed;
    
    // Calculate wobble effect - different wobble for different parts of sprite
    float xWobble = sin(time + originalPos.y * 5.0) * vertexWobbleAmount;
    float yWobble = cos(time * 0.7 + originalPos.x * 5.0) * vertexWobbleAmount;
    
    // Apply wobble to position
    vec2 wobbledPos = originalPos.xy + vec2(xWobble, yWobble);
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(wobbledPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates
    v_TexCoord3 = v_TexCoord;
} 