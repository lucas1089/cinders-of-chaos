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

// Rainbow Ripple parameters
float rainbowSpeed = 0.5; // Slowed down color transitions
float rippleFrequency = 2.0; // Frequency of ripples
float rippleAmplitude = 0.008; // Intensity of ripple distortion

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Normalized offset for ripple effect (-1 to 1 range)
    vec2 normalizedOffset = offsetFromCenter / 24.0;
    
    // Calculate distance from center for ripple
    float distFromCenter = length(normalizedOffset);
    
    // Create expanding ripple waves
    float ripplePhase = distFromCenter * rippleFrequency - u_Time;
    float ripple = sin(ripplePhase * 3.14159 * 2.0);
    
    // Apply ripple displacement in radial direction
    vec2 rippleDir = normalize(normalizedOffset);
    vec2 displacement = rippleDir * ripple * rippleAmplitude * distFromCenter;
    
    // Apply displacement to position
    vec2 finalPos = origPosition.xy + displacement;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass time for rainbow color and ripple information
    v_TexCoord3 = vec2(u_Time * rainbowSpeed, distFromCenter);
} 