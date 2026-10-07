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

// Plasmic Toxic parameters
float blobSpeed = 0.3; // Slower, sludgy movement
float distortionAmount = 0.009; // Medium distortion for toxic ooze effect

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate the distance from center
    float distFromCenter = length(normalizedPos);
    
    // Create toxic/acid-like distortion patterns
    // Bubbling, churning effect with slower frequencies
    float distortion1 = sin(normalizedPos.x * 2.0 + normalizedPos.y * 3.0 + u_Time * blobSpeed);
    float distortion2 = sin(normalizedPos.x * 3.5 - normalizedPos.y * 1.5 + u_Time * blobSpeed * 0.5);
    float distortion3 = cos(normalizedPos.x * 1.0 + normalizedPos.y * 4.0 + u_Time * blobSpeed * 0.7);
    
    // Add a bubbling effect that's stronger at certain spots
    float bubbleEffect = sin(normalizedPos.x * 8.0 + normalizedPos.y * 8.0 + u_Time * blobSpeed * 2.0);
    bubbleEffect = smoothstep(0.7, 0.9, bubbleEffect) * 0.5; // Isolate peaks for bubble effect
    
    // Combine distortions with bubble effect
    float combinedDistortion = (distortion1 * 0.4 + distortion2 * 0.3 + distortion3 * 0.3) * distortionAmount;
    combinedDistortion += bubbleEffect * distortionAmount * 0.5; // Add bubble distortion
    
    // Direction of distortion (radial for general ooze effect)
    vec2 distortionDir = normalize(normalizedPos);
    
    // Better handling for center point
    if (length(normalizedPos) < 0.01) {
        distortionDir = vec2(0.0, 1.0);
    }
    
    // Apply distortion
    vec2 finalPos = origPosition.xy + distortionDir * combinedDistortion;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position, time, and bubble effect to fragment shader
    v_TexCoord3 = vec2(distFromCenter, u_Time * blobSpeed);
} 