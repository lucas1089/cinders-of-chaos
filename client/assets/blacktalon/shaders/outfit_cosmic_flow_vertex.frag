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

// Cosmic flow parameters
float flowWaveAmplitude = 0.004; // Amplitude of the cosmic flow waves
float flowWaveFrequency = 3.0;   // Frequency of the cosmic flow waves
float flowSpeed = 1.5;           // Speed of the flow animation

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate distance from center (0 to 1 range)
    float distFromCenter = length(normalizedPos);
    
    // Calculate angular position (0 to 2π)
    float angle = atan(normalizedPos.y, normalizedPos.x);
    
    // Create cosmic flow wave effect
    // Multiple overlapping wave patterns for more complex movement
    float wave1 = sin(angle * 2.0 + u_Time * flowSpeed) * flowWaveAmplitude;
    float wave2 = sin(angle * 3.0 - u_Time * flowSpeed * 0.7) * flowWaveAmplitude * 0.7;
    float wave3 = sin(normalizedPos.x * flowWaveFrequency + u_Time * flowSpeed * 0.5) * flowWaveAmplitude * 0.5;
    float wave4 = sin(normalizedPos.y * flowWaveFrequency * 1.3 - u_Time * flowSpeed * 0.3) * flowWaveAmplitude * 0.5;
    
    // Combine waves
    float waveX = wave1 + wave3;
    float waveY = wave2 + wave4;
    
    // Scale effect by distance from center (more at the edges)
    float edgeFactor = smoothstep(0.0, 0.8, distFromCenter);
    waveX *= edgeFactor;
    waveY *= edgeFactor;
    
    // Apply cosmic flow displacement
    vec2 finalPos = origPosition.xy + vec2(waveX, waveY);
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized information for fragment shader
    v_TexCoord3 = vec2(distFromCenter, angle);
} 