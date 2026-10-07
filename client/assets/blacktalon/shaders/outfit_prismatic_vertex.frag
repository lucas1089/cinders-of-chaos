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

// Prismatic parameters
float arrowSpeed = 1.5; // Reduced speed of diagonal lines (was 3.0)
float subtleDistortion = 0.003; // Reduced distortion for smoother appearance (was 0.005)

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate the distance from center for moon glow effect
    float distFromCenter = length(normalizedPos);
    
    // Apply subtle wavy displacement based on distance from center
    // Smoother sine wave with reduced frequency for less jagged transitions
    float angle = atan(normalizedPos.y, normalizedPos.x);
    float waveDisplacement = sin(angle * 2.0 + u_Time * 0.3) * subtleDistortion; // Reduced frequency and speed
    
    // Add a second wave with different frequency for more natural movement
    waveDisplacement += sin(angle * 1.0 - u_Time * 0.2) * subtleDistortion * 0.5;
    
    // Apply smooth falloff at edges to prevent jagged transitions
    float edgeFalloff = smoothstep(0.0, 0.8, distFromCenter);
    waveDisplacement *= edgeFalloff;
    
    // Calculate final position with smoother radial displacement
    vec2 finalPos = origPosition.xy;
    finalPos += normalize(offsetFromCenter) * waveDisplacement * distFromCenter;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass position and time information to fragment shader
    // x: distance from center (for moon glow)
    // y: normalized angle (for diagonal lines)
    // This helps create the diagonal flowing arrows effect
    float normalizedAngle = (angle + 3.14159) / 6.28318; // 0 to 1 range
    v_TexCoord3 = vec2(distFromCenter, normalizedAngle);
} 