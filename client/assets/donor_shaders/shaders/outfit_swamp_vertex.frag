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

// Swamp parameters
float swampSpeed = 0.6; // Speed of swamp movement
float swampWaveSize = 0.012; // Size of swamp waves
float spinIntensity = 0.008; // Intensity of spin effect
float dashIntensity = 0.015; // Intensity of dash effect

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate the distance from center and angle
    float distFromCenter = length(normalizedPos);
    float angle = atan(normalizedPos.y, normalizedPos.x);
    
    // Create gooey swamp waves
    // Multiple overlapping sin waves create an uneven gooey effect
    float swampWave1 = sin(normalizedPos.x * 4.0 + normalizedPos.y * 3.0 + u_Time * swampSpeed);
    float swampWave2 = sin(normalizedPos.x * 2.5 - normalizedPos.y * 5.0 + u_Time * swampSpeed * 0.7);
    float swampWave3 = sin(normalizedPos.y * 3.0 + u_Time * swampSpeed * 1.3);
    
    // Combine waves for gooey effect
    float swampWave = (swampWave1 * 0.4 + swampWave2 * 0.4 + swampWave3 * 0.2) * swampWaveSize;
    
    // Create spin effect that alternates with dashing
    // Cycle between spinning and dashing movements
    float cycleTime = u_Time * 0.2; // Slow overall cycle
    float cycleFraction = fract(cycleTime);
    
    // Create spin effect (first half of cycle)
    float spinAmount = 0.0;
    if (cycleFraction < 0.5) {
        // Normalize the spin phase to 0-1 range
        float spinPhase = cycleFraction * 2.0; // 0 to 1 during spin phase
        
        // Calculate spin that increases then decreases
        float spinCurve = sin(spinPhase * 3.14159); // Peaks in the middle of spin phase
        
        // Rotate position based on spin
        float spinAngle = spinCurve * 0.5; // Max half rotation
        float newAngle = angle + spinAngle;
        
        // Convert back to cartesian coordinates
        spinAmount = spinIntensity * spinCurve;
    }
    
    // Create dash effect (second half of cycle)
    float dashX = 0.0;
    float dashY = 0.0;
    if (cycleFraction >= 0.5) {
        // Normalize the dash phase to 0-1 range
        float dashPhase = (cycleFraction - 0.5) * 2.0; // 0 to 1 during dash phase
        
        // Create quick dash then slow return
        float dashCurve = 0.0;
        if (dashPhase < 0.3) {
            // Quick dash out
            dashCurve = dashPhase / 0.3; // 0 to 1 quickly
        } else {
            // Slower return
            dashCurve = 1.0 - ((dashPhase - 0.3) / 0.7); // 1 to 0 more slowly
        }
        
        // Dash in random direction based on cycle number
        float dashAngle = floor(cycleTime) * 2.3; // Different angle each cycle
        dashX = cos(dashAngle) * dashCurve * dashIntensity;
        dashY = sin(dashAngle) * dashCurve * dashIntensity;
    }
    
    // Apply all effects
    vec2 finalPos = origPosition.xy;
    
    // Apply swamp waves (stronger near edges, weaker in center)
    finalPos += normalize(offsetFromCenter) * swampWave * distFromCenter;
    
    // Apply spin (rotate around center)
    float spinX = cos(angle + spinAmount) - cos(angle);
    float spinY = sin(angle + spinAmount) - sin(angle);
    finalPos.x += spinX * distFromCenter * 24.0;  
    finalPos.y += spinY * distFromCenter * 24.0;
    
    // Apply dash (whole body moves)
    finalPos.x += dashX * 24.0;
    finalPos.y += dashY * 24.0;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass distance from center, cycle info, and original angle
    v_TexCoord3 = vec2(distFromCenter, cycleFraction);
} 