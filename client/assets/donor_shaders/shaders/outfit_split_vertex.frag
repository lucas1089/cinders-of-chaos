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

// Split effect parameters
float splitWidth = 3.0; // How far to shift the left part (in pixels)
float waveSpeed = 1.2; // Speed of the waves
float waveAmplitude = 2.0; // Size of the waves
float waveFrequency = 8.0; // Frequency of waves

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate final position
    vec2 finalPos = origPosition.xy;
    
    // Split the character - only affect left half
    // Determine if this vertex is on the left side of the sprite
    if (offsetFromCenter.x < 0.0) {
        // Shift left side slightly to the left
        finalPos.x -= splitWidth;
        
        // Calculate the horizontal distance from the split line (midpoint)
        float distFromSplit = abs(offsetFromCenter.x);
        
        // Apply a wave effect along the split edge
        // The closer to the split edge, the stronger the wave
        float waveEdgeFactor = smoothstep(24.0, 0.0, distFromSplit); // Stronger near edge
        
        // Create multiple sin waves with different frequencies for more organic look
        float wave1 = sin(offsetFromCenter.y * 0.2 + u_Time * waveSpeed) * waveAmplitude;
        float wave2 = sin(offsetFromCenter.y * 0.5 + u_Time * waveSpeed * 1.3) * (waveAmplitude * 0.5);
        float wave3 = sin(offsetFromCenter.y * waveFrequency * 0.1 + u_Time * waveSpeed * 0.7) * (waveAmplitude * 0.3);
        
        // Combine waves
        float waveOffset = (wave1 + wave2 + wave3) * waveEdgeFactor;
        
        // Apply the wave horizontally
        finalPos.x += waveOffset;
    }
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos.xy, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates
    v_TexCoord3 = v_TexCoord;
} 