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

// Electric GoldGreen parameters
float flowSpeed = 1.5; // Speed of flowing movement
float distortionAmount = 0.01; // Amount of distortion (reduced from 0.012)
float waveFrequency = 3.5; // Frequency of waves (reduced from 4.0)

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create diagonal value for fragment shader
    float diagonal = normalizedPos.x + normalizedPos.y;
    
    // Create smooth flowing distortion using multiple sine waves
    float wave1 = sin(diagonal * waveFrequency + u_Time * flowSpeed);
    float wave2 = sin(normalizedPos.x * waveFrequency * 1.2 + u_Time * flowSpeed * 0.8);
    float wave3 = sin(normalizedPos.y * waveFrequency * 1.3 + u_Time * flowSpeed * 0.9);
    float wave4 = sin((normalizedPos.x - normalizedPos.y) * waveFrequency * 0.8 - u_Time * flowSpeed * 1.1);
    
    // Calculate glitter effect with smoother transitions
    float glitterPhase = sin(u_Time * 0.8) * 0.5 + 0.5;
    float glitterIntensity = pow(glitterPhase, 3.0); // Smoother peak for glitter
    
    // Combine waves for X displacement with varying influence
    float displacementX = wave1 * 0.4 + wave2 * 0.3 + wave4 * 0.3;
    // Combine waves for Y displacement with varying influence
    float displacementY = wave1 * 0.4 + wave3 * 0.3 + wave4 * 0.3;
    
    // Apply distortion with smooth amplitude modulation
    float distortionMod = (sin(u_Time * 1.2) * 0.2 + 0.8); // Subtle pulsing of distortion amount
    vec2 finalDisplacement = vec2(displacementX, displacementY) * distortionAmount * distortionMod;
    
    // Add subtle glitter amplification
    finalDisplacement *= (1.0 + glitterIntensity * 0.8);
    
    // Apply smooth displacement to position
    vec2 finalPos = origPosition.xy + finalDisplacement;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass diagonal value and glitter intensity to fragment shader
    v_TexCoord3 = vec2(diagonal, glitterIntensity);
} 