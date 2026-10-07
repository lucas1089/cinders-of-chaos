uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_FrostCoord;
varying float v_GlowFactor;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Pseudo-random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Frost pattern function
float frostPattern(vec2 uv, float scale, float time) {
    // Create crystalline patterns using multiple sine waves at different frequencies
    float pattern = 0.0;
    pattern += 0.5 * sin(uv.x * scale * 1.0 + uv.y * scale * 1.7 + time * 0.2);
    pattern += 0.25 * sin(uv.x * scale * 2.1 - uv.y * scale * 1.3 - time * 0.3);
    pattern += 0.125 * sin(uv.x * scale * 3.3 + uv.y * scale * 2.9 + time * 0.5);
    pattern += 0.0625 * sin(uv.x * scale * 4.7 - uv.y * scale * 4.1 - time * 0.7);
    return (pattern * 0.5 + 0.5); // Normalize to 0-1 range
}

void main()
{
    gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 effectColor = texture2D(u_Tex1, v_TexCoord3);
    
    if(texcolor.a > 0.9) {
        // Calculate frost overlay pattern
        float frost = frostPattern(v_FrostCoord, 20.0, u_Time);
        
        // Base ice effect - blue with slight cyan tint, modulated by glow factor
        float effectIntensity = 1.25 * (0.8 + 0.4 * v_GlowFactor);
        gl_FragColor *= effectColor * effectIntensity;
        
        // Apply frost color with pulsing glow factor
        gl_FragColor.r *= 0.4 + 0.3 * frost;  // Reduced red, more with frost
        gl_FragColor.g *= 0.7 + 0.3 * frost;  // Slightly reduced green, more with frost
        gl_FragColor.b *= 1.0 + 0.8 * v_GlowFactor;  // Enhanced blue with glow pulse
        
        // Apply additional frosty blue glow that pulses
        vec3 frostyGlow = vec3(0.5, 0.7, 1.2) * frost * v_GlowFactor;
        gl_FragColor.rgb += frostyGlow * 0.4;
        
        // Get approximate texture size from texcoord deltas
        vec2 dx = dFdx(v_TexCoord * 256.0);
        vec2 dy = dFdy(v_TexCoord * 256.0);
        float texSize = max(length(dx), length(dy));
        float sizeScale = 32.0 / texSize; // Scale relative to 32x32 textures
        
        // Ice glimmering particles with glow modulation
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.003 * sizeScale; // Smaller sparkles for crystal-like appearance
        float sparkleIntensity = 0.9 * (0.7 + 0.5 * v_GlowFactor); // Intensity modulated by glow
        
        // Add sparkle points with balanced frequencies
        for (int i = 0; i < 8; i++) { // More types of sparkles for ice crystal effect
            float timeOffset = float(i) * 1.05;
            float scale = (27.0 + float(i) * 25.0) / sizeScale; // Scale grid size inversely to texture size
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with ice crystal effect
            float sparkle = r * sin(u_Time * (2.2 + r * 1.8) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 3.3) * sparkleIntensity;
            
            // Lower threshold for sparkle visibility to show more particles
            if (sparkle > 0.2) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Sharp fade toward edges for crisp ice-like sparkles
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.6); // Sharper edges for ice crystals
                    
                    // Add ice-colored sparkle to fragment color (blue/cyan) with glow influence
                    vec3 sparkleColor = mix(vec3(0.3, 0.8, 2.0), vec3(0.5, 0.9, 2.2), v_GlowFactor);
                    gl_FragColor.rgb += sparkleColor * sparkle * fade * 1.5;
                }
            }
        }
        
        // Add ice rim frost effect along edges using texture alpha gradient
        float edgeDetect = length(vec2(dFdx(texcolor.a), dFdy(texcolor.a)));
        float rimFrost = smoothstep(0.0, 0.4, edgeDetect) * v_GlowFactor;
        gl_FragColor.rgb = mix(gl_FragColor.rgb, vec3(0.7, 0.9, 1.2), rimFrost * 0.7);
        
        // Enhance texture opacity based on glow factor (brighter = more visible)
        float texOpacityBoost = 0.7 + 0.4 * v_GlowFactor; // 0.7 to 1.1 range
        gl_FragColor.rgb = mix(gl_FragColor.rgb, effectColor.rgb * vec3(0.5, 0.7, 1.5), 
                              (1.0 - texOpacityBoost) * 0.3);
        
        // Add pulsing glow for ice effect synchronized with glow factor
        float glowPulse = 0.12 * v_GlowFactor;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add subtle color shifting between blue and cyan for dynamic crystal effect
        float colorShift = sin(u_Time * 1.5) * 0.08 + 0.08;
        gl_FragColor.r -= colorShift * 0.1;
        gl_FragColor.g += colorShift * 0.3;
        gl_FragColor.b += colorShift * (0.3 + 0.2 * v_GlowFactor);
        
        // Enhance brightness for ice shine based on glow factor
        gl_FragColor.rgb *= 1.0 + 0.2 * v_GlowFactor;
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 