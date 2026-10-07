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

// Goofy Stretchy parameters
float stretchSpeed = 1.0; // Speed of stretch animation
float stretchAmount = 0.4; // Maximum amount of stretch/squash
float wobbleSpeed = 3.0; // Speed of head wobble
float wobbleAmount = 0.03; // Amount of head wobble

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate phase for stretch/squash cycle
    float stretchPhase = fract(u_Time * stretchSpeed * 0.5); // 0 to 1
    
    // Calculate stretch factor - we want to oscillate between stretching tall and squashing flat
    float stretchFactor;
    if (stretchPhase < 0.5) {
        // 0 to 0.5 - stretch vertically
        stretchFactor = sin(stretchPhase * 3.14159) * stretchAmount;
    } else {
        // 0.5 to 1 - squash horizontally
        stretchFactor = -sin((stretchPhase - 0.5) * 3.14159) * stretchAmount;
    }
    
    // Apply stretch/squash transformation
    // When stretchFactor is positive, stretch vertically and squash horizontally
    // When negative, do the opposite
    vec2 stretchedPos = offsetFromCenter;
    if (stretchFactor > 0.0) {
        // Stretch vertically, squash horizontally
        stretchedPos.y *= (1.0 + stretchFactor);
        stretchedPos.x *= (1.0 - stretchFactor * 0.5);
    } else {
        // Stretch horizontally, squash vertically
        stretchedPos.x *= (1.0 - stretchFactor * 0.5);
        stretchedPos.y *= (1.0 + stretchFactor);
    }
    
    // Add a goofy head wobble for the upper part of the sprite
    if (normalizedPos.y < -0.1) { // Upper part of sprite (y decreases going up)
        float wobblePhase = u_Time * wobbleSpeed;
        float headWobble = sin(wobblePhase) * wobbleAmount;
        stretchedPos.x += headWobble * (abs(normalizedPos.y) + 0.1) * 5.0; // More wobble at the top
    }
    
    // Recombine position with center
    vec2 finalPos = spriteCenter + stretchedPos;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position and stretch data
    v_TexCoord3 = vec2(normalizedPos.y, stretchFactor);
} 