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
        // Base ruby effect - deep red with slight pink tint
        gl_FragColor *= effectColor * 1.25;
        gl_FragColor.r *= 1.4;  // Enhance red
        
        // Ruby glimmering particles
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.005; // Slightly smaller sparkles for gem-like appearance
        float sparkleIntensity = 0.9; // Slightly higher intensity for gem-like shine
        
        // Add sparkle points with balanced frequencies
        for (int i = 0; i < 5; i++) { // 5 types of sparkles for more varied effect
            float timeOffset = float(i) * 1.2;
            float scale = 20.0 + float(i) * 22.0;
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with more dramatic effect for gem-like shine
            float sparkle = r * sin(u_Time * (3.0 + r * 2.5) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 3.5) * sparkleIntensity;
            
            // Balanced threshold for sparkle visibility
            if (sparkle > 0.25) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Strong fade toward edges for crisp gem-like sparkles
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.5);
                    
                    // Add ruby-colored sparkle to fragment color (red with pink tint)
                    gl_FragColor.rgb += vec3(1.6, 0.4, 0.7) * sparkle * fade * 1.7;
                }
            }
        }
        
        // Add pulsing glow for gem-like effect
        float glowPulse = 0.12 * sin(u_Time * 2.2) + 0.12;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add subtle color shifting between red and pink for dynamic sparkle
        float colorShift = sin(u_Time * 1.8) * 0.08 + 0.08;
        gl_FragColor.r += colorShift * 0.8;
        gl_FragColor.g -= colorShift * 0.3;
        gl_FragColor.b += colorShift * 0.5;
        
        // Enhance brightness for gem-like shine
        gl_FragColor.rgb *= 1.15;
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 