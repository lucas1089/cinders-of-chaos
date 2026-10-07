uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Shockwave parameters
float shockwaveIntensity = 0.7; // Intensity of the shockwave glow
float energyIntensity = 0.6; // Intensity of the energy effect
float wavePulseFrequency = 2.0; // Frequency of wave pulsation

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get wave information from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float waveEffect = v_TexCoord3.y;
    
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
    
    // Create energy wave time
    float waveTime = u_Time * wavePulseFrequency;
    
    // Create energy wave colors
    vec3 coreColor = vec3(0.1, 0.5, 1.0); // Blue core
    vec3 waveColor = vec3(0.5, 0.8, 1.0); // Light blue wave
    vec3 outerColor = vec3(0.0, 0.2, 0.8); // Darker blue outer
    
    // Create wave pulse effect
    float wavePulse = sin(waveTime) * 0.5 + 0.5;
    
    // Create center energy core glow
    float coreGlow = smoothstep(0.4, 0.0, distFromCenter);
    
    // Create wave ripple glow
    float waveGlow = waveEffect * shockwaveIntensity;
    
    // Apply color effects based on distance and wave effect
    vec3 finalColor = baseColor.rgb;
    
    // Add center energy core
    finalColor = mix(finalColor, coreColor, coreGlow * energyIntensity * (0.7 + 0.3 * wavePulse));
    
    // Add wave energy color
    finalColor = mix(finalColor, waveColor, waveGlow * 0.6);
    
    // Add glow based on wave effect
    finalColor += waveColor * waveGlow * 0.4;
    
    // Add outer energy glow
    float outerGlow = smoothstep(0.5, 0.9, distFromCenter) * 0.4 * wavePulse;
    finalColor = mix(finalColor, outerColor, outerGlow * energyIntensity);
    
    // Add electric arc effects
    // Create electrical zaps that emanate from center
    float zap1 = step(0.95, sin(atan(v_TexCoord.y - 0.5, v_TexCoord.x - 0.5) * 20.0 + waveTime * 5.0));
    float zap2 = step(0.95, sin(atan(v_TexCoord.y - 0.5, v_TexCoord.x - 0.5) * 15.0 - waveTime * 7.0));
    
    // Combine zaps and apply distance falloff
    float zapEffect = (zap1 + zap2) * 0.5 * smoothstep(0.0, 0.7, distFromCenter) * 
                      smoothstep(1.0, 0.7, distFromCenter);
    
    // Add electric zaps
    finalColor += waveColor * zapEffect * energyIntensity;
    
    // Add subtle overall blue tint
    finalColor = mix(finalColor, finalColor * vec3(0.8, 0.9, 1.0), 0.2);
    
    // Final color
    gl_FragColor = vec4(finalColor, baseColor.a);
} 