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

// Rainbow Mutation parameters
float rainbowSpeed = 3.0; // Moderate rainbow color changes (reduced from 10.0)
float bounceSpeed = 1.5; // Slower bounce speed (reduced from 3.0)
float bounceHeight = 0.08; // How high to bounce (reduced from 0.15)
float stretchFactor = 0.1; // Stretching at top of bounce (reduced from 0.2)
float squashFactor = 0.15; // Squashing at landing (reduced from 0.3)

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate bounce position - more natural bounce
    float bouncePhase = fract(u_Time * bounceSpeed * 0.5); // Complete cycle
    
    // Create bounce curve - smoother and more natural
    float bounceCurve;
    if (bouncePhase < 0.3) {
        // Smoother launch
        bounceCurve = bouncePhase / 0.3; // 0 to 1 more gradually
    } else if (bouncePhase < 0.7) {
        // Peak of jump - more time at top
        float topPhase = (bouncePhase - 0.3) / 0.4; // 0 to 1 at top
        bounceCurve = 1.0 - 4.0 * (topPhase - 0.5) * (topPhase - 0.5); // Parabola
    } else {
        // Smoother fall
        float fallPhase = (bouncePhase - 0.7) / 0.3; // 0 to 1 during fall
        bounceCurve = 1.0 - fallPhase * fallPhase; // Ease-in
    }
    
    // Apply vertical offset for bounce
    float verticalOffset = bounceCurve * bounceHeight;
    
    // Apply stretching at the peak and squashing at landing - more subtle
    if (bouncePhase > 0.3 && bouncePhase < 0.7) {
        // Stretch at the peak - more subtle
        float stretchAmount = sin((bouncePhase - 0.3) * 3.14159 / 0.4) * stretchFactor;
        
        // Apply stretching (taller and slightly thinner)
        offsetFromCenter.y *= (1.0 + stretchAmount);
        offsetFromCenter.x *= (1.0 - stretchAmount * 0.3);
    }
    
    // Squashing at landing (more natural compression)
    if (bouncePhase > 0.9 || bouncePhase < 0.1) {
        // Calculate squash amount
        float squashPhase;
        if (bouncePhase > 0.9) {
            squashPhase = (bouncePhase - 0.9) / 0.1;
        } else {
            squashPhase = 1.0 - bouncePhase / 0.1;
        }
        
        float squashAmount = squashPhase * squashFactor;
        
        // Apply squashing (shorter and wider)
        offsetFromCenter.y *= (1.0 - squashAmount);
        offsetFromCenter.x *= (1.0 + squashAmount * 0.5);
    }
    
    // No random jitter - removed epilepsy effect
    
    // Recombine position with center and apply bounce
    vec2 finalPos = spriteCenter + offsetFromCenter;
    finalPos.y -= verticalOffset; // Subtract because y decreases going up
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass time and bounce data to fragment shader
    v_TexCoord3 = vec2(u_Time * rainbowSpeed, bouncePhase);
} 