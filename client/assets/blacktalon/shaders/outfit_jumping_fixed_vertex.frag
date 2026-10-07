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

// Fixed Jumping parameters
float jumpCycleTime = 3.0; // 3 second jump cycle (1.5 up, 1.5 down)
float jumpHeight = 0.2; // Maximum height of jump
float stretchFactor = 0.12; // How much to stretch at the peak
float squashFactor = 0.18; // How much to squash at landing

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate jump cycle phase (0 to 1)
    float jumpTime = mod(u_Time, jumpCycleTime);
    float jumpPhase = jumpTime / jumpCycleTime; // 0 to 1 over 3 seconds
    
    // Create jump curve
    // First half (0-0.5): going up with ease out
    // Second half (0.5-1): falling down with ease in
    float jumpCurve;
    
    if (jumpPhase < 0.5) {
        // Going up (first 1.5 seconds): ease-out curve
        float upPhase = jumpPhase * 2.0; // 0 to 1 during first half
        jumpCurve = 1.0 - (1.0 - upPhase) * (1.0 - upPhase); // Ease out
    } else {
        // Coming down (last 1.5 seconds): ease-in curve
        float downPhase = (jumpPhase - 0.5) * 2.0; // 0 to 1 during second half
        jumpCurve = 1.0 - downPhase * downPhase; // Ease in
    }
    
    // Apply stretching at the peak and squashing at landing
    if (jumpPhase > 0.4 && jumpPhase < 0.6) {
        // Stretch at the peak
        float stretchPhase = 1.0 - abs(jumpPhase - 0.5) * 10.0; // 0 to 1 near peak
        float stretchAmount = stretchPhase * stretchFactor;
        
        // Apply stretching (taller and slightly thinner)
        offsetFromCenter.y *= (1.0 + stretchAmount);
        offsetFromCenter.x *= (1.0 - stretchAmount * 0.3);
    }
    
    // Squashing at landing (end of cycle)
    if (jumpPhase > 0.9) {
        // Calculate squash amount, increasing as we approach phase 1.0
        float squashPhase = (jumpPhase - 0.9) * 10.0; // 0 to 1 at landing
        float squashAmount = squashPhase * squashFactor;
        
        // Apply squashing (shorter and wider)
        offsetFromCenter.y *= (1.0 - squashAmount);
        offsetFromCenter.x *= (1.0 + squashAmount * 0.5);
    }
    
    // Also apply squashing at the beginning of the cycle (continuing from previous landing)
    if (jumpPhase < 0.1) {
        // Calculate squash amount, decreasing as we leave phase 0
        float squashPhase = (0.1 - jumpPhase) * 10.0; // 1 to 0 at start
        float squashAmount = squashPhase * squashFactor;
        
        // Apply squashing (shorter and wider)
        offsetFromCenter.y *= (1.0 - squashAmount);
        offsetFromCenter.x *= (1.0 + squashAmount * 0.5);
    }
    
    // Recombine position with center
    vec2 finalPos = spriteCenter + offsetFromCenter;
    
    // IMPORTANT FIX: Apply vertical jump offset to the ENTIRE sprite, not just forward movement
    // Subtract because Y decreases going up in screen coordinates
    finalPos.y -= jumpCurve * jumpHeight; 
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass jump phase and curve to fragment shader
    v_TexCoord3 = vec2(jumpPhase, jumpCurve);
} 