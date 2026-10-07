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

// Plasmic Ocean parameters
float waveSpeed = 0.6; // Speed of ocean waves
float distortionAmount = 0.01; // Amount of wave distortion
float waveFrequency = 2.0; // Frequency of waves

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Create normalized position for distortion (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create horizontal wave patterns (ocean waves)
    float wave1 = sin(normalizedPos.y * waveFrequency + u_Time * waveSpeed);
    float wave2 = sin(normalizedPos.y * waveFrequency * 0.7 + u_Time * waveSpeed * 1.3);
    float wave3 = sin(normalizedPos.y * waveFrequency * 1.3 - u_Time * waveSpeed * 0.7);
    
    // Combine waves for ocean effect - primarily horizontal movement
    float waveDistortion = wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2;
    
    // Apply distortion - primarily horizontal for water motion
    vec2 distortion = vec2(
        waveDistortion,                           // Primary horizontal wave motion
        sin(waveDistortion + u_Time) * 0.3        // Slight vertical component
    ) * distortionAmount;
    
    // Scale distortion by distance from center
    float distFromCenter = length(normalizedPos);
    distortion *= 0.5 + distFromCenter * 0.5; // More at edges
    
    // Apply distortion to position
    vec2 finalPos = origPosition.xy + distortion;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass wave distortion and normalized position to fragment shader
    v_TexCoord3 = vec2(waveDistortion, distFromCenter);
} 