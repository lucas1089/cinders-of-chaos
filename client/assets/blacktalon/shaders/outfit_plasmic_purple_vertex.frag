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

// Plasmic Purple parameters
float plasmaSpeed = 0.7; // Speed of plasma animation
float distortionAmount = 0.009; // Amount of distortion

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Create normalized position for distortion (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create plasma distortion
    float plasma1 = sin(normalizedPos.x * 3.0 + u_Time * plasmaSpeed);
    float plasma2 = sin(normalizedPos.y * 3.0 + u_Time * plasmaSpeed * 1.2);
    float plasma3 = sin((normalizedPos.x + normalizedPos.y) * 2.0 - u_Time * plasmaSpeed * 0.8);
    
    // Combine plasma waves for pulsating effect
    float plasmaDistortion = plasma1 * plasma2 * plasma3;
    
    // Apply distortion to position
    vec2 distortion = vec2(
        sin(plasmaDistortion * 2.0 + u_Time * 1.2),
        cos(plasmaDistortion * 2.0 + u_Time * 0.9)
    ) * distortionAmount;
    
    // Scale distortion by distance from center (more at edges)
    distortion *= length(normalizedPos);
    
    // Apply distortion to position
    vec2 finalPos = origPosition.xy + distortion;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass plasma distortion and normalized position to fragment shader
    v_TexCoord3 = vec2(plasmaDistortion, length(normalizedPos));
} 