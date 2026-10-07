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

// Electric Eel parameters
float lightningSpeed = 2.0; // Speed of electrical current
float distortionAmount = 0.015; // Amount of electrical distortion
float electricFrequency = 5.0; // Frequency of electric waves
float burstsSpeed = 3.0; // Speed of light bursts

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create curved diagonal electrical pattern
    // Use sine waves with different frequencies to create curved diagonal pattern
    float diagonal = normalizedPos.x + normalizedPos.y; // Basic diagonal
    float curve = sin(diagonal * 3.14159 * electricFrequency + u_Time * lightningSpeed);
    
    // Create electrical distortion in diagonal direction
    float electric1 = sin(diagonal * electricFrequency + u_Time * lightningSpeed);
    float electric2 = sin(diagonal * electricFrequency * 1.5 - u_Time * lightningSpeed * 1.2);
    float electric3 = sin(diagonal * electricFrequency * 0.7 + u_Time * lightningSpeed * 0.8);
    
    // Calculate burst effect - random bursts of activity
    float burstPhase = fract(u_Time * 0.3); // Cycle for bursts
    float burstIntensity = pow(sin(burstPhase * 3.14159), 10.0); // Sharp peaks for bursts
    
    // Combine electrical effects with bursts
    float electricDisplacementX = (electric1 * 0.7 + electric2 * 0.3) * distortionAmount;
    float electricDisplacementY = (electric2 * 0.7 + electric3 * 0.3) * distortionAmount;
    
    // Amplify during burst
    electricDisplacementX *= (1.0 + burstIntensity * 2.0);
    electricDisplacementY *= (1.0 + burstIntensity * 2.0);
    
    // Apply electrical displacement
    vec2 finalPos = origPosition.xy + vec2(electricDisplacementX, electricDisplacementY);
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass diagonal value, burst intensity and time to fragment shader
    v_TexCoord3 = vec2(diagonal, burstIntensity);
} 