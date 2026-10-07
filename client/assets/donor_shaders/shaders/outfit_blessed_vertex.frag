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

// Blessed parameters
float pulseSpeed = 0.8; // Speed of holy pulse
float haloSize = 0.04; // Size of expanding holy halo
float raySpeed = 1.2; // Speed of ray rotation

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Distance from center
    float distFromCenter = length(normalizedPos);
    
    // Create subtle expanding halo effect
    float pulsePhase = fract(u_Time * pulseSpeed);
    float haloRadius = pulsePhase * 1.0; // Halo expands from 0 to 1.0 in normalized space
    
    // Calculate how close this vertex is to the current halo ring
    float haloFactor = 1.0 - abs(distFromCenter - haloRadius) / haloSize;
    haloFactor = max(0.0, haloFactor);
    
    // Apply subtle expansion along the halo
    vec2 haloOffset = normalize(normalizedPos) * haloFactor * 0.02;
    
    // Calculate angel rays effect (radial expansion that rotates)
    float angle = atan(normalizedPos.y, normalizedPos.x);
    float rayPhase = sin(angle * 8.0 + u_Time * raySpeed) * 0.5 + 0.5;
    float rayFactor = rayPhase * max(0.0, 1.0 - distFromCenter) * 0.015;
    
    // Apply ray expansion
    vec2 rayOffset = normalize(normalizedPos) * rayFactor;
    
    // Combine offsets
    vec2 finalOffset = haloOffset + rayOffset;
    
    // Calculate final position
    vec2 finalPos = origPosition.xy + finalOffset;
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position, distance from center, and time to fragment shader
    v_TexCoord3 = vec2(distFromCenter, u_Time);
} 