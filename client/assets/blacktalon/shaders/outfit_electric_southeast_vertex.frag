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

// Electric Southeast parameters
float lightningSpeed = 1.5; // Speed of electrical current
float distortionAmount = 0.012; // Amount of electrical distortion
float electricFrequency = 3.0; // Lower frequency for more spacing between lines
float burstsSpeed = 0.5; // Speed of dark cloud pulsation
float cloudPulseFreq = 0.2; // Frequency of cloud pulsation
float cloudIntensity = 0.5; // Intensity of dark cloud effect

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create diagonal southeast direction (down-right) - positive in both x and y
    float diagonal = normalizedPos.x * 0.7 + normalizedPos.y * 1.3; // More y weight for southeast
    
    // Create electrical distortion with more spacing
    float electric1 = sin(diagonal * electricFrequency + u_Time * lightningSpeed);
    float electric2 = sin(diagonal * electricFrequency * 0.8 - u_Time * lightningSpeed * 1.2);
    float electric3 = sin(diagonal * electricFrequency * 0.5 + u_Time * lightningSpeed * 0.8);
    
    // Calculate burst effect - dark cloud pulsation
    float burstPhase = u_Time * cloudPulseFreq;
    float burstIntensity = (sin(burstPhase * 3.14159) * 0.5 + 0.5) * cloudIntensity;
    
    // Create additional slow pulsating wave for dark cloud effect
    float cloudWave = sin(u_Time * burstsSpeed * 0.3) * 0.5 + 0.5;
    float cloudEffect = sin(normalizedPos.x * 2.0 + normalizedPos.y * 2.0 + u_Time * 0.5) * cloudWave;
    
    // Combine electrical effects
    float electricDisplacementX = (electric1 * 0.6 + electric2 * 0.3 + cloudEffect * 0.1) * distortionAmount;
    float electricDisplacementY = (electric2 * 0.6 + electric3 * 0.3 + cloudEffect * 0.1) * distortionAmount;
    
    // Amplify during burst (dark cloud pulsation)
    electricDisplacementX *= (1.0 + burstIntensity);
    electricDisplacementY *= (1.0 + burstIntensity);
    
    // Apply southeast direction bias - make displacement more pronounced in SE direction
    electricDisplacementX += burstIntensity * 0.002; // Slight constant shift right during bursts
    electricDisplacementY += burstIntensity * 0.002; // Slight constant shift down during bursts
    
    // Apply electrical displacement
    vec2 finalPos = origPosition.xy + vec2(electricDisplacementX, electricDisplacementY);
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass diagonal value, burst intensity and cloud effect to fragment shader
    v_TexCoord3 = vec2(diagonal, burstIntensity);
} 