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

// Bubble parameters
float bubbleSpeed = 0.8; // Speed of bubble animations
float bubbleDistortion = 0.01; // Amount of bubble distortion
float pulseFrequency = 3.0; // How often bubbles pulse

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate distance from center
    float distFromCenter = length(normalizedPos);
    
    // Create bubble distortion
    // This creates multiple overlapping bubble-like distortions
    
    // Create several bubble waves at different frequencies and phases
    float bubble1 = sin(distFromCenter * 6.0 - u_Time * bubbleSpeed * 1.1) * 0.5 + 0.5;
    float bubble2 = sin(distFromCenter * 9.0 - u_Time * bubbleSpeed * 0.7) * 0.5 + 0.5;
    float bubble3 = sin(distFromCenter * 12.0 - u_Time * bubbleSpeed * 0.9) * 0.5 + 0.5;
    
    // Combine bubble waves
    float bubbleWave = (bubble1 * 0.5 + bubble2 * 0.3 + bubble3 * 0.2);
    
    // Create pop effect
    // Cycle through different sections of the sprite for popping
    float popPhase = fract(u_Time * 0.4); // Slower cycle for pops
    float popAngle = atan(normalizedPos.y, normalizedPos.x); // -PI to PI range
    float normalizedAngle = (popAngle + 3.14159) / 6.28318; // 0 to 1 range
    
    // Determine if this section is popping
    float popSection = floor(normalizedAngle * 8.0); // 8 sections
    float popSectionPhase = fract(popSection * 0.125 + u_Time * 0.2); // Different phase per section
    
    // Pop effect - expands then contracts quickly
    float popEffect = 0.0;
    if (popSectionPhase < 0.2) {
        // Expand then contract
        popEffect = sin(popSectionPhase * 3.14159 * 5.0) * 0.02;
    }
    
    // Calculate pulse effect
    float pulsePhase = fract(u_Time * 0.25); // Slow cycle
    float globalPulse = sin(pulsePhase * 3.14159 * 2.0) * 0.015;
    
    // Combine effects - apply distortion in the direction away from center
    vec2 bubbleDistortionVec = normalize(normalizedPos) * (bubbleWave * bubbleDistortion + globalPulse + popEffect);
    
    // Ensure we have a valid direction vector
    if (length(normalizedPos) < 0.01) {
        bubbleDistortionVec = vec2(0.0, 0.0);
    }
    
    // Apply distortion
    vec2 finalPos = origPosition.xy + bubbleDistortionVec;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position and center distance for fragment shader
    v_TexCoord3 = vec2(distFromCenter, normalizedAngle); // Pack info for fragment shader
} 