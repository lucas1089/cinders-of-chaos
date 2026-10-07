uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Pseudo-random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main()
{
    gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 effectColor = texture2D(u_Tex1, v_TexCoord3);
    
    if(texcolor.a > 0.9) {
        // Base cosmos effect - deep blue with starry accents
        gl_FragColor *= effectColor * 1.25;
        gl_FragColor.r *= 0.6;  // Reduce red
        gl_FragColor.g *= 0.7;  // Reduce green
        gl_FragColor.b *= 1.4;  // Enhance blue for cosmic appearance
        
        // Get approximate texture size from texcoord deltas
        vec2 dx = dFdx(v_TexCoord * 256.0);
        vec2 dy = dFdy(v_TexCoord * 256.0);
        float texSize = max(length(dx), length(dy));
        float sizeScale = 32.0 / texSize; // Scale relative to 32x32 textures
        
        // Cosmos glimmering particles (stars)
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.002 * sizeScale; // Tiny stars
        float sparkleIntensity = 1.2; // Higher intensity for stars
        
        // Add sparkle points with balanced frequencies
        for (int i = 0; i < 15; i++) { // Many types of sparkles for dense starfield
            float timeOffset = float(i) * 0.6;
            float scale = (40.0 + float(i) * 25.0) / sizeScale; // Scale grid size inversely to texture size
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with twinkling star effect
            float sparkle = r * sin(u_Time * (1.2 + r * 1.5) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 2.5) * sparkleIntensity;
            
            // Lower threshold for sparkle visibility to show more particles
            if (sparkle > 0.15) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Strong fade toward edges for crisp star-like sparkles
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.2); // Less power for sharper stars
                    
                    // Multi-colored star particles to mimic a cosmic sky
                    vec3 starColor;
                    float starType = fract(r * 7.919);
                    
                    if (starType < 0.15) {
                        // Blue-white stars (hot)
                        starColor = vec3(0.8, 0.9, 1.8);
                    } else if (starType < 0.3) {
                        // Yellow stars (medium)
                        starColor = vec3(1.8, 1.6, 0.8);
                    } else if (starType < 0.45) {
                        // Red stars (cool)
                        starColor = vec3(1.7, 0.7, 0.7);
                    } else if (starType < 0.6) {
                        // Purple/pink stars (distant galaxies)
                        starColor = vec3(1.4, 0.7, 1.8);
                    } else if (starType < 0.85) {
                        // White stars (neutral)
                        starColor = vec3(1.6, 1.6, 1.6);
                    } else {
                        // Cyan/teal stars (special)
                        starColor = vec3(0.5, 1.6, 1.4);
                    }
                    
                    // Add cosmos-colored sparkle to fragment color
                    gl_FragColor.rgb += starColor * sparkle * fade * 1.5;
                }
            }
        }
        
        // Add pulsing nebula glow for cosmic effect
        float glowPulse = 0.12 * sin(u_Time * 0.8) + 0.12;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add subtle color shifting for nebula-like effect
        float colorShift = sin(u_Time * 0.6) * 0.1 + 0.1;
        gl_FragColor.r += colorShift * 0.2;
        gl_FragColor.g += colorShift * 0.1;
        gl_FragColor.b += colorShift * 0.3;
        
        // Enhance darkness of space
        gl_FragColor.rgb *= 0.9;
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 