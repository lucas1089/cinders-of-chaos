uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Flame Knight parameters
float flameGlowIntensity = 0.8; // Intensity of flame glow
float smokeIntensity = 0.3; // Intensity of smoke effect
float sparkDensity = 20.0; // Density of sparks

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get flame information from vertex shader
    float flameFactor = v_TexCoord3.x;
    float flamePattern = v_TexCoord3.y;
    
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
    
    // Create flame animation time
    float flameTime = u_Time * 1.2;
    
    // Create dynamic flame color gradient
    vec3 flameBase = vec3(1.0, 0.3, 0.0); // Orange/red base
    vec3 flameMiddle = vec3(1.0, 0.6, 0.0); // Brighter orange
    vec3 flameTip = vec3(1.0, 0.9, 0.2); // Yellow tip
    
    // Create flame gradient based on pattern and factor
    vec3 flameColor = mix(
        mix(flameBase, flameMiddle, flamePattern),
        flameTip,
        flamePattern * flamePattern // Square for more yellow at the very tips
    );
    
    // Add dark smoke effect
    vec3 smokeColor = vec3(0.1, 0.1, 0.1);
    
    // Create smoke pattern (above the flames)
    float smokePattern = sin(v_TexCoord.x * 8.0 + flameTime) * sin(v_TexCoord.y * 8.0 - flameTime * 0.5);
    smokePattern = pow(smokePattern * 0.5 + 0.5, 3.0); // Make smoke more billowy
    
    // Only add smoke at top of flames
    float smokeAmount = flameFactor * smoothstep(0.5, 0.9, flamePattern) * smokeIntensity;
    
    // Generate sparks (small bright particles)
    float sparkPattern = fract(sin(v_TexCoord.x * sparkDensity - flameTime * 2.0) * 
                             sin(v_TexCoord.y * sparkDensity + flameTime)) * flameFactor;
    
    // Make sparks small and bright
    float sparkAmount = step(0.98, sparkPattern) * flameFactor;
    
    // Apply flame effect
    // Add flames primarily at the edges
    vec3 finalColor = baseColor.rgb;
    
    // Add dark smoke
    finalColor = mix(finalColor, smokeColor, smokeAmount * smokePattern);
    
    // Add flame color
    float flameAmount = flameFactor * flameGlowIntensity;
    finalColor = mix(finalColor, flameColor, flameAmount * 0.5);
    finalColor += flameColor * flameAmount * flamePattern * 0.3; // Add glow
    
    // Add sparks
    finalColor += vec3(1.0, 0.9, 0.6) * sparkAmount;
    
    // Add inner glow to the character
    vec3 innerGlow = mix(flameBase * 0.5, flameTip * 0.3, flamePattern);
    finalColor += innerGlow * flameFactor * 0.2;
    
    // Final color
    gl_FragColor = vec4(finalColor, baseColor.a);
} 