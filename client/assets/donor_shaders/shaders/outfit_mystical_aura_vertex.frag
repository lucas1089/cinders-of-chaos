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

// Mystical Aura parameters
float auraWidth = 0.15; // Width of the aura effect
float auraSpeed = 0.8; // Speed of aura movement
float auraIntensity = 0.007; // Intensity of aura displacement

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
    
    // Direction from center (normalized)
    vec2 dirFromCenter = normalizedPos / max(distFromCenter, 0.001);
    
    // Create aura effect based on distance from center
    // The aura should be more intense at the edges of the sprite
    float auraFactor = smoothstep(0.4, 0.9, distFromCenter);
    
    // Create fluctuating aura effect
    float auraTime = u_Time * auraSpeed;
    
    // Create multiple layers of aura waves
    float auraWave1 = sin(distFromCenter * 10.0 - auraTime * 1.1);
    float auraWave2 = sin(distFromCenter * 15.0 - auraTime * 0.7 + 1.0);
    float auraWave3 = sin(distFromCenter * 7.0 - auraTime * 1.3 + 2.0);
    
    // Combine aura waves for a more complex effect
    float auraPulse = (auraWave1 * 0.5 + auraWave2 * 0.3 + auraWave3 * 0.2);
    
    // Create spiraling effect
    float angle = atan(normalizedPos.y, normalizedPos.x);
    float spiralWave = sin(angle * 5.0 + auraTime * 2.0) * 0.5 + 0.5;
    
    // Combine aura and spiral effects
    float combinedEffect = auraPulse * 0.7 + spiralWave * 0.3;
    
    // Calculate displacement amount
    float displacementAmount = auraFactor * combinedEffect * auraIntensity;
    
    // Apply displacement along the direction from center
    vec2 displacement = dirFromCenter * displacementAmount;
    
    // Apply displacement to position
    vec2 finalPos = origPosition.xy + displacement;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass aura information to fragment shader
    v_TexCoord3 = vec2(distFromCenter, combinedEffect * 0.5 + 0.5);
} 