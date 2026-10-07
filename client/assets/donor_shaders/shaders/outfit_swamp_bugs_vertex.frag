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

// Swamp with bugs parameters
float swampSpeed = 1.0; // Speed of swamp movement
float swampDistortion = 0.012; // Amount of swamp swirl distortion
float bugSpeed = 3.0; // Speed of bug movement
float bugAmount = 0.7; // Amount of bugs

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized offset for swamp effect (-1 to 1 range)
    vec2 normalizedOffset = offsetFromCenter / 24.0;
    
    // Distance from center (0 to 1)
    float distFromCenter = length(normalizedOffset);
    
    // Angle from center
    float angle = atan(normalizedOffset.y, normalizedOffset.x);
    
    // Create swirling distortion pattern (more at edges)
    float swirl = sin(angle * 2.0 + u_Time * swampSpeed);
    swirl *= distFromCenter; // More effect at edges
    
    // Calculate radial swamp movement
    float radialPulsation = sin(distFromCenter * 5.0 - u_Time * swampSpeed * 0.7);
    
    // Apply distortion based on swirling pattern
    vec2 distortion = vec2(
        sin(swirl + u_Time * swampSpeed),
        cos(swirl + u_Time * swampSpeed * 1.2)
    );
    
    // Scale distortion by distance from center and distortion amount
    distortion *= distFromCenter * swampDistortion;
    
    // Add radial component
    distortion += normalize(normalizedOffset) * radialPulsation * swampDistortion * 0.5;
    
    // Apply distortion to position
    vec2 finalPos = origPosition.xy + distortion;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position and time to fragment shader for bug effect
    v_TexCoord3 = vec2(u_Time * bugSpeed, distFromCenter);
} 