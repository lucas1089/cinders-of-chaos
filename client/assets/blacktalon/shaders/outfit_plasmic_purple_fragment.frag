uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Plasmic Purple parameters
float plasmicIntensity = 0.7; // Intensity of plasmic effect
float pulseFrequency = 0.5; // Frequency of pulsation
float orbCount = 4.0; // Number of plasmic orbs

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
    
    // Get plasma distortion and distance from center
    float plasmaDistortion = v_TexCoord3.x;
    float distFromCenter = v_TexCoord3.y;
    
    // Create global pulsating effect
    float pulse = sin(u_Time * pulseFrequency) * 0.5 + 0.5;
    
    // Calculate plasma orbs effect - several moving blobs
    float orbs = 0.0;
    for(float i = 0.0; i < orbCount; i++) {
        // Calculate orbit position for this orb
        float angle = u_Time * (0.3 + i * 0.2) + i * (3.14159 * 2.0 / orbCount);
        float radius = 0.4 + sin(u_Time * 0.2 + i) * 0.1; // Varying orbit radius
        
        // Calculate orb center position
        vec2 orbCenter = vec2(
            sin(angle) * radius,
            cos(angle) * radius
        );
        
        // Normalized texture coordinates (centered, -1 to 1)
        vec2 normalizedCoord = v_TexCoord * 2.0 - 1.0;
        
        // Calculate distance to orb
        float orbDist = distance(normalizedCoord, orbCenter);
        
        // Create smooth orb with falloff
        float orbSize = 0.3 + sin(u_Time * 0.7 + i * 1.5) * 0.1; // Varying size
        float thisOrb = smoothstep(orbSize, orbSize * 0.5, orbDist);
        
        // Add this orb to the total
        orbs += thisOrb;
    }
    
    // Combine orbs with plasma distortion
    float finalPlasma = orbs * 0.5 + (plasmaDistortion * 0.5 + 0.5) * 0.5;
    
    // Purple color palette for plasmic effect
    vec3 color1 = vec3(0.6, 0.1, 0.8); // Dark purple
    vec3 color2 = vec3(0.9, 0.2, 1.0); // Bright purple
    vec3 color3 = vec3(0.4, 0.0, 0.6); // Deep purple
    vec3 color4 = vec3(0.7, 0.0, 1.0); // Vivid purple
    
    // Mix colors based on plasma value and pulse
    vec3 mixColor1 = mix(color1, color2, finalPlasma);
    vec3 mixColor2 = mix(color3, color4, 1.0 - finalPlasma);
    vec3 plasmicColor = mix(mixColor1, mixColor2, pulse);
    
    // Add glow based on plasma value
    float glowAmount = finalPlasma * pulse * 0.7;
    vec3 glowColor = mix(vec3(0.7, 0.0, 1.0), vec3(1.0, 0.5, 1.0), finalPlasma);
    
    // Apply plasmic effect with distance and pulse modulation
    float effectIntensity = plasmicIntensity * (0.7 + 0.3 * pulse);
    baseColor.rgb = mix(baseColor.rgb, plasmicColor, effectIntensity * (0.5 + 0.5 * finalPlasma));
    
    // Add glow
    baseColor.rgb += glowColor * glowAmount * 0.3;
    
    // Set output color
    gl_FragColor = baseColor;
} 