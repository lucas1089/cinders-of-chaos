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

// Whiplash parameters
float whipSpeed = 1.5; // Speed of whip motion
float whipHeight = 0.04; // Height of whip motion
float whipWidth = 0.02; // Width of whip motion
float snapFactor = 2.5; // How fast the snap is (higher = faster snap)

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Create whiplash effect
    // Using asymmetric timing for a snap effect
    float whipPhase = fract(u_Time * whipSpeed); // 0 to 1 phase
    
    // Create a curve that moves slowly up then snaps back quickly
    // Using a modified sin curve with asymmetric timing
    float snapCurve;
    
    if (whipPhase < 0.7) {
        // Slower rise (70% of the time)
        snapCurve = sin(whipPhase * 3.14159 / 0.7) * 0.5; // 0 to 0.5
    } else {
        // Fast snap back (30% of the time)
        float snapPhase = (whipPhase - 0.7) / 0.3; // 0 to 1
        snapCurve = 0.5 - pow(snapPhase, snapFactor) * 0.5; // 0.5 to 0
    }
    
    // Calculate vertical whiplash motion
    float verticalWhip = snapCurve * whipHeight;
    
    // Calculate horizontal whiplash motion (slight trails)
    float horizontalWhip = 0.0;
    
    // Apply horizontal stretch at peak
    if (whipPhase > 0.5 && whipPhase < 0.7) {
        // Calculate a stretch factor based on Y position
        float stretchFactor = (offsetFromCenter.y / 24.0) * whipWidth;
        horizontalWhip = stretchFactor * sin((whipPhase - 0.5) * 3.14159 / 0.2);
    }
    
    // Apply whip distortion based on position in sprite
    // Top parts move more than bottom parts
    float positionFactor = (offsetFromCenter.y + 24.0) / 48.0; // 0 at bottom, 1 at top
    positionFactor = pow(positionFactor, 0.7); // Make the effect stronger on top
    
    // Calculate final position
    vec2 finalPos = origPosition.xy;
    finalPos.y += verticalWhip * positionFactor;
    finalPos.x += horizontalWhip * positionFactor;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates
    v_TexCoord3 = v_TexCoord;
} 