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

// Plasmic Fast parameters
float blobSpeed = 0.7; // Increased speed of the plasmic blobs
float distortionAmount = 0.012; // Increased amount of vertex distortion

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
    
    // More aggressive plasmic distortion with faster frequencies
    float distortion1 = sin(normalizedPos.x * 4.0 + normalizedPos.y * 3.0 + u_Time * blobSpeed);
    float distortion2 = sin(normalizedPos.x * 2.5 - normalizedPos.y * 3.5 + u_Time * blobSpeed * 0.9);
    float distortion3 = sin(normalizedPos.y * 3.0 + u_Time * blobSpeed * 1.5);
    
    // Combine distortions
    float combinedDistortion = (distortion1 * 0.5 + distortion2 * 0.3 + distortion3 * 0.2) * distortionAmount;
    
    // Direction of distortion (radial, flowing outward/inward)
    vec2 distortionDir = normalize(normalizedPos);
    
    // Better handling for center point
    if (length(normalizedPos) < 0.01) {
        distortionDir = vec2(0.0, 1.0); // Default to upward if at center
    }
    
    // Apply distortion
    vec2 finalPos = origPosition.xy + distortionDir * combinedDistortion;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position and time to fragment shader
    v_TexCoord3 = vec2(distFromCenter, u_Time * blobSpeed);
} 