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

// Vortex Glitter parameters
float waveAmplitude = 0.004;    // Amplitude of the wave
float waveFrequency = 2.0;      // Frequency of the wave
float upwardSpeed = 1.2;        // Speed of upward movement
float spinAmount = 0.003;       // Amount of spin effect

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate distance from center and angle
    float distFromCenter = length(normalizedPos);
    float angle = atan(normalizedPos.y, normalizedPos.x);
    
    // Create spiral vortex effect for vertices
    // Rotate more at the edges and based on time
    float spinFactor = distFromCenter * spinAmount;
    float spinAngle = u_Time * 1.5 * spinFactor;
    
    // Calculate new position based on spin
    float spinX = cos(spinAngle) * normalizedPos.x - sin(spinAngle) * normalizedPos.y;
    float spinY = sin(spinAngle) * normalizedPos.x + cos(spinAngle) * normalizedPos.y;
    
    // Apply upward flow effect
    float upwardPhase = fract(u_Time * upwardSpeed * 0.1 - distFromCenter * 2.0);
    float upwardStrength = sin(upwardPhase * 3.14159 * 2.0) * 0.5 + 0.5;
    
    // Create wave effect that spirals outward
    float wavePhase = angle * 3.0 + u_Time * waveFrequency;
    float wave = sin(wavePhase) * waveAmplitude * distFromCenter;
    
    // Combine effects
    vec2 distortion = vec2(
        spinX - normalizedPos.x + wave * cos(angle),
        spinY - normalizedPos.y + wave * sin(angle) - upwardStrength * 0.005
    );
    
    // Apply distortion with distance scaling (more at edges)
    distortion *= smoothstep(0.0, 0.8, distFromCenter);
    
    // Apply final position
    vec2 finalPos = origPosition.xy + distortion * 24.0;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass distortion data to fragment shader
    v_TexCoord3 = vec2(distFromCenter, angle);
} 