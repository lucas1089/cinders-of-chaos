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

// Turbo Rainbow parameters
float rainbowSpeed = 3.0; // Very fast color change
float wobbleAmount = 0.002; // Small wobble for extra effect

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Add a subtle wobble to make it more energetic
    vec2 wobble = vec2(
        sin(u_Time * 8.0 + offsetFromCenter.y * 0.1),
        cos(u_Time * 7.0 + offsetFromCenter.x * 0.1)
    ) * wobbleAmount;
    
    // Apply wobble to position
    vec2 finalPos = origPosition.xy + wobble;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass time and normalized position to fragment shader
    v_TexCoord3 = vec2(u_Time * rainbowSpeed, length(offsetFromCenter) / 24.0);
} 