uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Mystical Aura parameters
float auraIntensity = 0.8; // Intensity of the aura glow
float auraColorSpeed = 0.5; // Speed of color cycling
float particleCount = 15.0; // Number of particle effects

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample texture with normal coordinates
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Get aura information from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float auraEffect = v_TexCoord3.y;
    
    // Calculate aura factor based on distance from center
    // We want the aura to be more intense at the edges
    float auraFactor = smoothstep(0.5, 0.95, distFromCenter);
    
    // Create time-varying aura colors
    float auraTime = u_Time * auraColorSpeed;
    
    // Create a magical color palette that shifts over time
    vec3 color1 = vec3(0.2, 0.4, 1.0); // Blue
    vec3 color2 = vec3(0.8, 0.2, 1.0); // Purple
    vec3 color3 = vec3(0.2, 0.8, 0.6); // Teal
    
    // Cycle between colors over time
    float colorCycle1 = (sin(auraTime * 0.7) * 0.5 + 0.5);
    float colorCycle2 = (sin(auraTime * 0.5 + 2.1) * 0.5 + 0.5);
    
    // Mix colors based on time cycle
    vec3 auraColor1 = mix(color1, color2, colorCycle1);
    vec3 auraColor2 = mix(color2, color3, colorCycle2);
    vec3 finalAuraColor = mix(auraColor1, auraColor2, sin(auraTime * 0.3) * 0.5 + 0.5);
    
    // Add aura glow effect based on aura factor and effect
    vec3 auraTint = finalAuraColor * auraEffect;
    float auraBrightness = auraFactor * auraEffect * auraIntensity;
    
    // Apply aura to base color
    baseColor.rgb = mix(baseColor.rgb, auraTint, auraBrightness * 0.5);
    baseColor.rgb += auraTint * auraBrightness * 0.3; // Add some emissive glow
    
    // Add particle effects (magical sparkles)
    // Add several magic particles moving in different ways
    float particleBrightness = 0.0;
    
    for(float i = 0.0; i < particleCount; i++) {
        // Calculate unique particle phase and position
        float particlePhase = i / particleCount;
        float particleSpeed = 0.8 + i * 0.1;
        float particleSize = 0.02 + i * 0.005;
        
        // Define particle position (spiral pattern)
        float angle = particlePhase * 6.28 + u_Time * particleSpeed;
        float radius = 0.2 + sin(u_Time * 0.3 + i) * 0.1;
        
        // Calculate particle position
        vec2 particleCenter = vec2(
            sin(angle) * radius * distFromCenter, 
            cos(angle) * radius * distFromCenter
        );
        
        // Calculate distance to particle
        float distToParticle = length(v_TexCoord - v_TexCoord2 - particleCenter);
        
        // Create particle with soft edge
        float particle = smoothstep(particleSize, 0.0, distToParticle);
        
        // Pulse particle brightness
        particle *= sin(u_Time * 2.0 + i * 5.0) * 0.5 + 0.5;
        
        // Add particle to total brightness
        particleBrightness += particle;
    }
    
    // Add particles to base color - make them slightly brighter than the aura
    baseColor.rgb += finalAuraColor * particleBrightness * 0.6;
    
    // Add subtle overall glow based on aura effect
    baseColor.rgb += finalAuraColor * auraEffect * 0.1;
    
    // Make the edges of the character more transparent for ethereal look
    // but only slightly to maintain character visibility
    baseColor.a = mix(baseColor.a, baseColor.a * (1.0 - auraFactor * 0.1), auraEffect * 0.2);
    
    // Final color
    gl_FragColor = baseColor;
} 