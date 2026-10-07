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

// Shockwave parameters
float waveSpeed = 1.0; // Speed of wave propagation
float waveCount = 3.0; // Number of waves
float waveAmplitude = 0.012; // Wave amplitude

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
    
    // Create wave time
    float waveTime = u_Time * waveSpeed;
    
    // Create multiple propagating waves
    // Each wave starts from the center and moves outward
    float waveEffect = 0.0;
    
    for(float i = 0.0; i < waveCount; i++) {
        // Create wave phase offset for each wave
        float wavePhase = i / waveCount;
        
        // Wave radius expands over time
        float waveRadius = fract(waveTime + wavePhase);
        
        // Create circular wave pattern
        // Stronger at the wave front and fading behind
        float waveFront = smoothstep(0.0, 0.1, waveRadius) * smoothstep(0.3, 0.1, waveRadius);
        
        // Add wave effect with distance matching
        // Only have strong effect when distance matches wave radius
        float distMatch = smoothstep(0.1, 0.0, abs(distFromCenter - waveRadius));
        
        // Combine effect
        waveEffect += waveFront * distMatch;
    }
    
    // Create subtle constant pulsation in the center
    float centerPulse = sin(waveTime * 3.0) * 0.5 + 0.5;
    float centerEffect = smoothstep(0.3, 0.0, distFromCenter) * centerPulse * 0.3;
    
    // Combine wave and center effects
    float combinedEffect = waveEffect + centerEffect;
    
    // Apply displacement along direction from center
    vec2 displacement = dirFromCenter * combinedEffect * waveAmplitude;
    
    // Apply stronger effect to outer regions
    displacement *= smoothstep(0.2, 1.0, distFromCenter);
    
    // Apply displacement to position
    vec2 finalPos = origPosition.xy + displacement;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass wave information to fragment shader
    v_TexCoord3 = vec2(distFromCenter, combinedEffect);
} 