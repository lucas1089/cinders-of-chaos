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
float shockAmount = 0.004;      // Amount of lightning displacement
float shockFrequency = 2.0;     // Frequency of lightning bolts

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
    
    // Create lightning effect - sudden jerky movements
    float timeScale = u_Time * shockFrequency;
    
    // Random-like function to create lightning flashes
    float flash = pow(sin(timeScale) * 0.5 + 0.5, 20.0) * 3.0;
    flash += pow(sin(timeScale * 1.3) * 0.5 + 0.5, 10.0) * 2.0;
    flash += pow(sin(timeScale * 0.7) * 0.5 + 0.5, 15.0) * 2.5;
    flash = min(1.0, flash * 0.2);
    
    // Create electrical arc displacement
    float noisePattern = sin(angle * 9.0 + timeScale * 5.0) * 
                         cos(distFromCenter * 7.0 + timeScale * 3.0);
    
    // Add sudden jerky movements during flashes
    float shockStrength = shockAmount * flash * (0.3 + 0.7 * distFromCenter);
    
    vec2 displacement = vec2(
        sin(angle * 4.0 + timeScale * 3.0) * shockStrength * noisePattern,
        cos(angle * 4.0 + timeScale * 3.0) * shockStrength * noisePattern
    );
    
    // Add more chaotic jitter during flashes
    displacement += vec2(
        sin(normalizedPos.x * 20.0 + timeScale * 10.0) * flash * shockAmount * 0.3,
        cos(normalizedPos.y * 20.0 + timeScale * 10.0) * flash * shockAmount * 0.3
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
    v_TexCoord3 = vec2(distFromCenter, angle);
} 