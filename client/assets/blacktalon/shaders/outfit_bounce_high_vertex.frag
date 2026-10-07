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

// High Bounce parameters
float bounceHeight = 0.06; // Height of bounce (twice as high)
float bounceSpeed = 2.0; // Speed of bouncing
float squashFactor = 0.25; // Increased squash on landing
float stretchFactor = 0.12; // Increased stretch at peak

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate bounce position
    float bouncePhase = fract(u_Time * bounceSpeed * 0.4); // Slightly slower
    float bounceCurve = sin(bouncePhase * 3.14159); // Sine curve for bounce
    
    // Apply vertical offset for bounce
    float verticalOffset = bounceCurve * bounceHeight;
    
    // Apply stretch effect (taller and slightly thinner)
    // This creates more of a pure stretching rather than a "fat" appearance
    // Stretch more vertically and less horizontally
    if (bouncePhase > 0.4 && bouncePhase < 0.6) {
        // More stretch at the peak with better proportions
        float stretchAmount = stretchFactor * bounceCurve;
        
        // Apply more vertical stretch
        offsetFromCenter.y *= (1.0 + stretchAmount * 1.2);
        
        // Apply less horizontal thinning
        offsetFromCenter.x *= (1.0 - stretchAmount * 0.3);
    }
    // When at the bottom (phase near 0 or 1), squash more
    else if (bouncePhase < 0.15 || bouncePhase > 0.85) {
        // Squash - wider and shorter with more pronounced effect
        float squashAmount = squashFactor * (1.0 - abs(bounceCurve) * 10.0);
        offsetFromCenter.y *= (1.0 - squashAmount);
        offsetFromCenter.x *= (1.0 + squashAmount * 0.8);
    }
    
    // Recombine position with center plus bounce
    vec2 finalPos = spriteCenter + offsetFromCenter;
    finalPos.y += verticalOffset;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates
    v_TexCoord3 = v_TexCoord;
} 