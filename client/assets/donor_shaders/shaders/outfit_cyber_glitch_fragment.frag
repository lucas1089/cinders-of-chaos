uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Cyber Glitch parameters
float colorShiftIntensity = 0.3; // Intensity of color shift
float rgbSplitAmount = 0.004; // Amount of RGB color separation
float scanlineIntensity = 0.15; // Intensity of scanlines

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get glitch information from vertex shader
    float glitchPattern = v_TexCoord3.x;
    float dataStream = v_TexCoord3.y;
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Use constant time steps for sudden glitch changes
    float glitchTime = floor(u_Time * 1.5 * 4.0) / 4.0;
    
    // Create RGB color split effect
    vec2 redOffset = vec2(rgbSplitAmount * sin(glitchTime * 7.3), 0.0);
    vec2 greenOffset = vec2(0.0, rgbSplitAmount * sin(glitchTime * 5.7));
    vec2 blueOffset = vec2(-rgbSplitAmount * sin(glitchTime * 3.5), 0.0);
    
    // Sample texture with RGB color separation
    vec4 baseColor;
    
    // Apply RGB split based on glitch pattern
    if (glitchPattern > 0.1) {
        // Create RGB color split effect
        float r = texture2D(u_Tex0, v_TexCoord + redOffset * glitchPattern).r;
        float g = texture2D(u_Tex0, v_TexCoord + greenOffset * glitchPattern).g;
        float b = texture2D(u_Tex0, v_TexCoord + blueOffset * glitchPattern).b;
        baseColor = vec4(r, g, b, originalColor.a);
    } else {
        baseColor = originalColor;
    }
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Create scanline effect
    float scanline = step(0.5, fract(v_TexCoord.y * 20.0));
    scanline = mix(1.0, scanline, scanlineIntensity);
    
    // Tint towards cyan and magenta for cyberpunk look
    vec3 cyanTint = vec3(0.0, 1.0, 1.0);
    vec3 magentaTint = vec3(1.0, 0.0, 1.0);
    
    // Choose tint based on glitch pattern
    vec3 tintColor = mix(cyanTint, magentaTint, sin(glitchTime * 10.0) * 0.5 + 0.5);
    
    // Apply color shift with cyber tint
    baseColor.rgb = mix(baseColor.rgb, baseColor.rgb * tintColor, glitchPattern * colorShiftIntensity);
    
    // Add data stream effect - bright data lines
    if (dataStream > 0.1) {
        vec3 dataColor = vec3(0.0, 1.0, 1.0); // Bright cyan
        baseColor.rgb = mix(baseColor.rgb, dataColor, dataStream * 0.5);
    }
    
    // Add random noise based on glitch pattern
    float noise = fract(sin(v_TexCoord.x * 100.0 + v_TexCoord.y * 100.0 + glitchTime * 10.0) * 5000.0);
    baseColor.rgb = mix(baseColor.rgb, baseColor.rgb * (0.8 + noise * 0.4), glitchPattern * 0.3);
    
    // Apply scanline darkening
    baseColor.rgb *= scanline;
    
    // Add occasional white flash for more digital feel
    float flash = step(0.98, sin(glitchTime * 30.0));
    baseColor.rgb = mix(baseColor.rgb, vec3(1.0), flash * glitchPattern * 0.5);
    
    // Final color
    gl_FragColor = baseColor;
} 