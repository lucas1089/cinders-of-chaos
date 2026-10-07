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

// Glitch parameters
float glitchSpeed = 1.2; // Speed of vertex glitching
float glitchIntensity = 0.004; // Amount of vertex displacement

// Simple hash function
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

void main() {
    // Get transformed vertex position
    vec3 originalPos = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Generate time-based glitch effect
    float time = u_Time * glitchSpeed;
    
    // Create occasional position glitches
    vec2 glitchOffset = vec2(0.0, 0.0);
    
    // Create glitch only occasionally and in certain rows of pixels
    if (hash(floor(time * 2.0)) < 0.3) {
        // Only affect certain y-rows based on time
        if (fract(originalPos.y * 20.0 + time) < 0.2) {
            // Random x-offset based on y position
            glitchOffset.x = (hash(floor(originalPos.y * 20.0) + time) * 2.0 - 1.0) * glitchIntensity;
        }
    }
    
    // Create occasional y-jitter
    if (hash(floor(time * 3.0)) < 0.1) {
        glitchOffset.y = (hash(floor(originalPos.x * 20.0) + time) * 2.0 - 1.0) * glitchIntensity * 0.5;
    }
    
    // Apply glitch to position
    vec2 glitchedPos = originalPos.xy + glitchOffset;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(glitchedPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates
    v_TexCoord3 = v_TexCoord;
} 