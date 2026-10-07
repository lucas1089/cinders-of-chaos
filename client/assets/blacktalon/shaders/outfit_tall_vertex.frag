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

// Tall parameters
float verticalScale = 1.7; // Stretch vertically only
float horizontalScale = 0.9; // Slight horizontal squish to look thinner and taller

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Scale vertically (taller) and slightly squish horizontally (thinner)
    offsetFromCenter.y *= verticalScale; 
    offsetFromCenter.x *= horizontalScale;
    
    // Add subtle swaying motion to make the height more noticeable
    float swayFreq = 1.0;
    float swayAmp = 0.002;
    float swaying = sin(u_Time * swayFreq) * swayAmp * offsetFromCenter.y;
    
    // Apply the swaying to x position
    offsetFromCenter.x += swaying;
    
    // Recombine position to create tall sprite centered at same position
    vec2 finalPos = spriteCenter + offsetFromCenter;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized y position to fragment shader for gradient effect
    float normalizedY = (offsetFromCenter.y / (24.0 * verticalScale)) + 0.5; // 0 to 1
    v_TexCoord3 = vec2(normalizedY, 0.0);
} 