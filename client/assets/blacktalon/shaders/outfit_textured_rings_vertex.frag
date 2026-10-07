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

// Textured Pulsing Rings parameters
float waveAmplitude = 0.0035;    // Amplitude of the wave displacement
float pulseFrequency = 1.8;      // Frequency of the pulse effect
float verticalStretch = 0.0025;  // Amount of vertical stretching during pulse

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
    
    // Create pulsing wave effect
    // Circular wave that travels outward from the center
    float wave = sin(distFromCenter * 12.0 - u_Time * 2.0) * waveAmplitude;
    
    // Scale wave effect by distance from center (more at the edges)
    wave *= smoothstep(0.0, 0.7, distFromCenter);
    
    // Create global pulse effect
    float pulse = sin(u_Time * pulseFrequency) * 0.5 + 0.5;
    
    // Apply wave displacement in radial direction
    vec2 displacement = vec2(
        cos(angle) * wave,
        sin(angle) * wave
    );
    
    // Add vertical stretching during pulse
    displacement.y -= normalizedPos.y * verticalStretch * pulse;
    
    // Add flow effect - vertices move slightly upward over time
    displacement.y -= sin(u_Time * 0.8 + distFromCenter * 5.0) * 0.001;
    
    // Apply displacement
    vec2 finalPos = origPosition.xy + displacement * 24.0;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized information for fragment shader
    v_TexCoord3 = vec2(distFromCenter, angle);
} 