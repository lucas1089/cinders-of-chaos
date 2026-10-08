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

// Epilepsy Rainbow parameters
float rainbowSpeed = 10.0; // Extremely fast color changes
float bounceSpeed = 3.0; // Pogo stick bounce speed
float bounceHeight = 0.15; // How high to bounce
float stretchFactor = 0.2; // Stretching at top of bounce
float squashFactor = 0.3; // Squashing at landing

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate bounce position - skibidi toilet pogo stick style
    float bouncePhase = fract(u_Time * bounceSpeed * 0.5); // Complete cycle
    
    // Create bounce curve - sharp at bottom for pogo effect
    float bounceCurve;
    if (bouncePhase < 0.2) {
        // Quick launch - pogo spring effect
        bounceCurve = bouncePhase / 0.2; // 0 to 1 quickly
    } else if (bouncePhase < 0.7) {
        // Peak of jump - slow at top
        float topPhase = (bouncePhase - 0.2) / 0.5; // 0 to 1 at top
        bounceCurve = 1.0 - 4.0 * (topPhase - 0.5) * (topPhase - 0.5); // Parabola
    } else {
        // Quick fall
        float fallPhase = (bouncePhase - 0.7) / 0.3; // 0 to 1 during fall
        bounceCurve = 1.0 - fallPhase * fallPhase; // Ease-in
    }
    
    // Apply vertical offset for bounce
    float verticalOffset = bounceCurve * bounceHeight;
    
    // Apply stretching at the peak and squashing at landing
    if (bouncePhase > 0.3 && bouncePhase < 0.6) {
        // Stretch at the peak
        float stretchAmount = sin((bouncePhase - 0.3) * 3.14159 / 0.3) * stretchFactor;
        
        // Apply stretching (taller and slightly thinner)
        offsetFromCenter.y *= (1.0 + stretchAmount);
        offsetFromCenter.x *= (1.0 - stretchAmount * 0.3);
    }
    
    // Squashing at landing and beginning (pogo compression)
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
    
    // Add random jitter for epilepsy effect
    float jitterAmount = sin(u_Time * 30.0) * 0.002;
    offsetFromCenter += vec2(
        sin(u_Time * 20.0 + offsetFromCenter.y * 10.0) * jitterAmount,
        cos(u_Time * 25.0 + offsetFromCenter.x * 10.0) * jitterAmount
    );
    
    // Recombine position with center and apply bounce
    vec2 finalPos = spriteCenter + offsetFromCenter;
    finalPos.y -= verticalOffset; // Subtract because y decreases going up
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass time, bounce data and position to fragment shader
    v_TexCoord3 = vec2(u_Time * rainbowSpeed, bouncePhase);
} 