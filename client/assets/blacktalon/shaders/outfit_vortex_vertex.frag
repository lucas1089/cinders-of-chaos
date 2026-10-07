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

// Vortex parameters
float rotationSpeed = 0.8; // Speed of vortex rotation
float pullStrength = 0.013; // Strength of vortex pull
float spiralTightness = 3.0; // How tight the spiral is

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Normalized position (-1 to 1)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Distance from center
    float distFromCenter = length(normalizedPos);
    
    // Calculate angle from center
    float angle = atan(normalizedPos.y, normalizedPos.x);
    
    // Create vortex time
    float vortexTime = u_Time * rotationSpeed;
    
    // Calculate rotation matrix for spinning effect
    // The farther from center, the less rotation
    float rotationAmount = vortexTime * (1.0 - distFromCenter * 0.3);
    
    // Create rotation matrix
    float s = sin(rotationAmount);
    float c = cos(rotationAmount);
    mat2 rotationMatrix = mat2(c, -s, s, c);
    
    // Apply rotation to position
    vec2 rotatedPos = rotationMatrix * normalizedPos;
    
    // Calculate spiral factor
    // Points should follow a spiral pattern toward the center
    float spiralFactor = distFromCenter + vortexTime * 0.1;
    float spiralStrength = sin(spiralFactor * spiralTightness) * 0.5 + 0.5;
    
    // Calculate inward pull strength
    // Stronger pull closer to the center with a smooth falloff
    float pullFactor = smoothstep(1.0, 0.0, distFromCenter) * pullStrength;
    
    // Apply pull toward center with spiral motion
    vec2 displacement = normalize(rotatedPos) * spiralStrength * -pullFactor;
    
    // Apply displacement to position with rotation
    vec2 finalPos = origPosition.xy + displacement * 24.0;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass vortex information to fragment shader
    v_TexCoord3 = vec2(distFromCenter, spiralStrength);
} 