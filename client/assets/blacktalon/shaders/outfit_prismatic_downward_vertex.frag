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

// Prismatic Downward parameters
float lineSpeed = 1.2; // Speed of falling lines
float lineWidth = 0.05; // Width of prismatic lines
float distortionAmount = 0.005; // Amount of prismatic distortion

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Normalized position (-1 to 1)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create downward falling pattern (mostly vertical with slight angle)
    // Use primarily Y coordinate with small X influence for slight angle
    float downPattern = normalizedPos.y * 3.0 + normalizedPos.x * 0.5;
    
    // Calculate prismatic line pattern
    float linePattern = fract(downPattern - u_Time * lineSpeed);
    
    // Create distortion when point is near a line
    float lineEffect = smoothstep(lineWidth, 0.0, abs(linePattern - 0.5));
    
    // Apply distortion primarily downward with slight x component
    // More distortion at bottom of character to emphasize falling effect
    float yDistortion = -lineEffect * distortionAmount * (1.0 + normalizedPos.y); // More at bottom
    float xDistortion = lineEffect * distortionAmount * 0.3; // Slight sideways component
    
    // Apply distortion to position
    vec2 finalPos = origPosition.xy + vec2(xDistortion, yDistortion);
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass prismatic line information to fragment shader
    v_TexCoord3 = vec2(linePattern, lineEffect);
} 