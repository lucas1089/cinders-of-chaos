uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Mexican Fiesta parameters
float colorCycleSpeed = 1.5; // Speed of color cycling
float patternFrequency = 5.0; // Frequency of striped pattern
float vibrancyFactor = 0.5; // Intensity of bright colors
float glitterAmount = 0.12; // Amount of festive glitter effect

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
    
    // Extract data from v_TexCoord3
    float verticalPos = v_TexCoord3.x; // Vertical position in normalized space
    float currentTime = v_TexCoord3.y; // Time
    
    // Create vibrant Mexican color palette
    vec3 mexicanGreen = vec3(0.0, 0.7, 0.0); // Green like in Mexican flag
    vec3 mexicanRed = vec3(0.9, 0.15, 0.15); // Red like in Mexican flag
    vec3 mexicanYellow = vec3(1.0, 0.8, 0.0); // Vibrant yellow
    vec3 mexicanPink = vec3(1.0, 0.4, 0.7); // Vibrant pink (rosa mexicano)
    
    // Create horizontal striped pattern like a serape
    // Calculate different stripe patterns on Y axis
    float stripePattern = floor(fract(v_TexCoord.y * patternFrequency) * 4.0);
    
    // Add different colors based on the stripe pattern
    vec3 stripeColor = mexicanGreen; // Default
    if (stripePattern < 1.0) {
        stripeColor = mexicanGreen;
    } else if (stripePattern < 2.0) {
        stripeColor = mexicanRed;
    } else if (stripePattern < 3.0) {
        stripeColor = mexicanYellow;
    } else {
        stripeColor = mexicanPink;
    }
    
    // Create offset to make pattern move with the dance
    float patternOffset = sin(currentTime * 0.5 + v_TexCoord.y * 5.0) * 0.05;
    
    // Create zigzag pattern
    float zigzag = abs(fract(v_TexCoord.x * 8.0 + patternOffset + currentTime * 0.2) * 2.0 - 1.0);
    zigzag = smoothstep(0.3, 0.7, zigzag);
    
    // Add pattern to base color
    // Add colors differently based on vertical position
    if (verticalPos < -0.3) { // Sombrero area
        // Add more yellow to sombrero, with some zigzag pattern
        baseColor.rgb = mix(baseColor.rgb, mexicanYellow, zigzag * 0.5 * vibrancyFactor);
    } 
    else if (verticalPos < 0.3) { // Body/poncho area
        // Add striped pattern to poncho area
        baseColor.rgb = mix(baseColor.rgb, stripeColor, vibrancyFactor * 0.7);
        
        // Add zigzag pattern overlay for more festivity
        float zigzagIntensity = (1.0 - zigzag) * 0.3;
        baseColor.rgb = mix(baseColor.rgb, vec3(1.0), zigzagIntensity * vibrancyFactor);
    }
    else { // Legs/feet area
        // Add dancing fire-like effect to the bottom
        float flameEffect = fract(v_TexCoord.y * 3.0 - currentTime * 0.5);
        flameEffect = pow(flameEffect, 0.5);
        baseColor.rgb = mix(baseColor.rgb, mix(mexicanRed, mexicanYellow, flameEffect), flameEffect * 0.4 * vibrancyFactor);
    }
    
    // Add festive glitter effect
    float glitterPhase1 = fract(v_TexCoord.x * 15.0 + v_TexCoord.y * 10.0 + currentTime * 1.1);
    float glitterPhase2 = fract(v_TexCoord.x * 12.0 - v_TexCoord.y * 13.0 + currentTime * 0.9);
    float glitter = step(0.98, glitterPhase1) * step(0.98, glitterPhase2);
    
    // Add glitter with slight color variation
    if (glitter > 0.0) {
        float glitterHue = fract(currentTime * 0.3 + v_TexCoord.x * 3.0);
        vec3 glitterColor;
        
        if (glitterHue < 0.25) {
            glitterColor = mexicanYellow;
        } else if (glitterHue < 0.5) {
            glitterColor = mexicanRed;
        } else if (glitterHue < 0.75) {
            glitterColor = mexicanGreen;
        } else {
            glitterColor = mexicanPink;
        }
        
        baseColor.rgb = mix(baseColor.rgb, glitterColor, glitterAmount * 1.5);
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 