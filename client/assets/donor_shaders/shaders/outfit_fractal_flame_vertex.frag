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

// Parameters
float waveAmount = 0.003;     // Amount of fractal distortion 
float pulseFrequency = 1.5;   // Frequency of fractal pulsing

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate distance from center and angle
    float distFromCenter = length(normalizedPos);
    float angle = atan(normalizedPos.y, normalizedPos.x);
    
    // Create fractal displacement pattern
    float fractalTime = u_Time * 0.7;
    float pulse = sin(fractalTime * pulseFrequency) * 0.5 + 0.5;
    
    // Create complex movement for fractal effect
    float wavePattern = sin(angle * 5.0 + fractalTime) * cos(distFromCenter * 8.0 - fractalTime * 0.5);
    float waveStrength = waveAmount * pulse * (0.5 + 0.5 * distFromCenter);
    
    vec2 displacement = vec2(
        cos(angle * 3.0 + fractalTime) * waveStrength * wavePattern,
        sin(angle * 3.0 + fractalTime) * waveStrength * wavePattern
    );
    
    // Apply displacement to position
    vec2 finalPos = origPosition.xy + displacement * 24.0;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass additional information to fragment shader
    v_TexCoord3 = vec2(distFromCenter, angle + wavePattern * 0.2);
} 