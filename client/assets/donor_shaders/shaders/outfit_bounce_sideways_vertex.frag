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

// Sideways Bounce parameters
float bounceWidth = 0.03; // Width of bounce
float bounceSpeed = 2.0; // Speed of bouncing
float squashFactor = 0.15; // How much to squash on extreme positions
float stretchFactor = 0.05; // How much to stretch in the middle

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate bounce position
    float bouncePhase = fract(u_Time * bounceSpeed * 0.5); // 0 to 1 phase
    float bounceCurve = sin(bouncePhase * 3.14159); // Sine curve for bounce
    
    // Apply horizontal offset for bounce (sideways movement)
    float horizontalOffset = bounceCurve * bounceWidth;
    
    // Apply squash and stretch based on bounce phase
    float squashStretchFactor = 1.0;
    
    // When at the extremes (phase near 0 or 1), squash horizontally
    if (bouncePhase < 0.1 || bouncePhase > 0.9) {
        // Squash - shorter and wider
        squashStretchFactor = 1.0 - squashFactor * (1.0 - abs(bounceCurve) * 10.0);
        offsetFromCenter.y *= (1.0 + squashFactor * 0.5);
        offsetFromCenter.x *= squashStretchFactor;
    } 
    // When in the middle (phase near 0.5), stretch horizontally
    else if (bouncePhase > 0.4 && bouncePhase < 0.6) {
        // Stretch - taller and thinner
        squashStretchFactor = 1.0 + stretchFactor * bounceCurve;
        offsetFromCenter.y *= (1.0 - stretchFactor * 0.3);
        offsetFromCenter.x *= squashStretchFactor;
    }
    
    // Recombine position with center plus bounce
    vec2 finalPos = spriteCenter + offsetFromCenter;
    finalPos.x += horizontalOffset;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates
    v_TexCoord3 = v_TexCoord;
} 