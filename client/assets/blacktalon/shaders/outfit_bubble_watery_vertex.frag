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

// Bubble Watery parameters
float bubbleSpeed = 1.0; // Speed of bubble movement
float distortionAmount = 0.01; // Amount of bubble distortion
float waterWaveSpeed = 0.5; // Speed of water wave movement

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Normalized position (-1 to 1)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Distance from center
    float distFromCenter = length(normalizedPos);
    
    // Create water wave distortion effect (subtle wavy water)
    float waterWave1 = sin(normalizedPos.x * 3.0 + normalizedPos.y * 2.0 + u_Time * waterWaveSpeed);
    float waterWave2 = sin(normalizedPos.x * 2.0 - normalizedPos.y * 3.0 - u_Time * waterWaveSpeed * 1.2);
    
    // Combine water waves - subtle effect
    float waterDistortion = (waterWave1 * 0.6 + waterWave2 * 0.4) * 0.3;
    
    // Create bubble distortion (more bubbles rising through water)
    // Base horizontal position on noise-like pattern for natural placement
    float bubblePhase1 = sin(normalizedPos.x * 5.0 + normalizedPos.y * 3.0);
    float bubblePhase2 = sin(normalizedPos.x * 4.0 - normalizedPos.y * 7.0);
    float bubblePhase = bubblePhase1 * bubblePhase2; // Creates a more complex pattern
    
    // Calculate vertical bubble movement (bubbles rising)
    float bubblePattern = fract(normalizedPos.y * 2.0 - u_Time * bubbleSpeed + bubblePhase);
    
    // Create smooth bubble shape
    float bubbleShape = smoothstep(0.4, 0.6, bubblePattern) - smoothstep(0.6, 0.8, bubblePattern);
    
    // Apply more bubble distortion at edges for bubble shape
    float bubbleDistortion = bubbleShape * distFromCenter * 1.5;
    
    // Combine water waves and bubble distortion
    vec2 distortion = vec2(
        waterDistortion + bubbleDistortion * 0.3,  // X distortion
        waterDistortion - bubbleDistortion * 0.7   // Y distortion (more upward for bubbles)
    ) * distortionAmount;
    
    // Apply distortion to position
    vec2 finalPos = origPosition.xy + distortion;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass bubble and water information to fragment shader
    v_TexCoord3 = vec2(bubblePattern, waterDistortion * 0.5 + 0.5);
}