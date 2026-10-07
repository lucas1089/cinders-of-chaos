uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Electric GoldGreen parameters
float waveFrequency = 5.0; // Frequency of sine waves
float electricIntensity = 0.6; // Intensity of electric effect
float glitterIntensity = 0.7; // Intensity of glitter effect
float flowSpeed = 2.5; // Flow speed of the effect

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
    
    // Get texture from goldgreen_pattern with flowing movement
    vec2 patternCoord = v_TexCoord;
    patternCoord.x += sin(v_TexCoord.y * 10.0 + u_Time * 1.2) * 0.03;
    patternCoord.y += cos(v_TexCoord.x * 8.0 + u_Time * 1.0) * 0.03;
    vec4 patternColor = texture2D(u_Tex1, fract(patternCoord * 2.0));
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Extract data from vertex shader
    float diagonal = v_TexCoord3.x; // Diagonal position value
    float glitter = v_TexCoord3.y; // Glitter intensity
    
    // Create sinusoidal electric pattern with smoother waves
    float wave1 = sin(diagonal * waveFrequency + u_Time * flowSpeed);
    float wave2 = sin(diagonal * waveFrequency * 1.5 + u_Time * flowSpeed * 1.2);
    float wave3 = sin(v_TexCoord.x * 8.0 + v_TexCoord.y * 8.0 + u_Time * 1.8);
    
    // Combine waves with smooth transitions
    float wavePattern = (wave1 * 0.5 + 0.5) * 0.6 + (wave2 * 0.5 + 0.5) * 0.4;
    wavePattern *= (wave3 * 0.3 + 0.7); // Add subtle variation
    
    // Apply gold-green electric color
    vec3 electricColor = vec3(0.9, 0.8, 0.2); // Gold base
    vec3 secondaryColor = vec3(0.2, 0.8, 0.3); // Green accent
    
    // Pulse between gold and green with smooth transition
    float pulse = sin(u_Time * 1.5) * 0.5 + 0.5;
    vec3 finalElectricColor = mix(electricColor, secondaryColor, pulse);
    
    // Apply subtle background pattern from goldgreen_pattern
    vec3 patternEffect = patternColor.rgb * vec3(0.8, 0.9, 0.4); // Gold-green tint for pattern
    baseColor.rgb = mix(baseColor.rgb, patternEffect, 0.15);
    
    // Apply electric effect with sinusoidal intensity
    baseColor.rgb = mix(baseColor.rgb, finalElectricColor, wavePattern * electricIntensity);
    
    // Apply glitter effect with smooth transitions
    if(glitter > 0.05) {
        // Gold-green glitter with smooth falloff
        float glitterMask = glitter * glitterIntensity;
        
        // Apply glitter with sinusoidal pattern
        float glitterEffect = wavePattern * glitterMask;
        
        // Apply smooth glitter highlight
        baseColor.rgb = mix(baseColor.rgb, mix(finalElectricColor, vec3(1.0), 0.6), glitterEffect);
        
        // Add subtle sparkles with smooth transitions
        float sparkle = sin(v_TexCoord.x * 100.0 + v_TexCoord.y * 100.0 + u_Time * 10.0) * 0.5 + 0.5;
        sparkle = pow(sparkle, 8.0) * glitterMask; // Softer sparkles
        
        // Apply sparkles with smooth falloff
        baseColor.rgb = mix(baseColor.rgb, vec3(1.0, 1.0, 0.8), sparkle * 0.7);
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 