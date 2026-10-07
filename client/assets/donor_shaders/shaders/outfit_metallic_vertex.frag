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

// Metallic parameters
float reflectionSpeed = 0.6; // Speed of reflection movement
float reflectionIntensity = 0.04; // Intensity of reflective highlights
float armorSegmentSize = 0.15; // Size of armor segments/plates

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create subtle armor plate movement
    // Different segments of armor move slightly differently
    vec2 armorSegment = floor(normalizedPos / armorSegmentSize);
    float segmentVariation = sin(armorSegment.x * 3.1 + armorSegment.y * 2.7 + u_Time * 0.5) * 0.5 + 0.5;
    
    // Create a small offset that mimics armor plates shifting slightly
    vec2 plateOffset = vec2(
        sin(u_Time * 0.5 + normalizedPos.y * 2.0) * 0.002 * segmentVariation,
        cos(u_Time * 0.4 + normalizedPos.x * 2.0) * 0.002 * segmentVariation
    );
    
    // Calculate final position with plate movement
    vec2 finalPos = origPosition.xy + plateOffset;
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position and time to fragment shader
    // Also pass angle and segment information
    float angle = atan(normalizedPos.y, normalizedPos.x);
    v_TexCoord3 = vec3(normalizedPos.x, normalizedPos.y, u_Time).xy;
} 