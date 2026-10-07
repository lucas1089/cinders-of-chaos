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

// Retro pixelated parameters
float jitterAmount = 0.001; // Amount of CRT jitter

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Apply vertical jitter to simulate CRT effect
    float jitter = sin(u_Time * 10.0) * jitterAmount;
    vec2 jitterOffset = vec2(0.0, jitter);
    
    // Calculate final position
    vec2 finalPos = origPosition.xy + jitterOffset;
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass texture coordinate and time to fragment shader for pixelation
    v_TexCoord3 = vec2(a_TexCoord.x, a_TexCoord.y);
} 