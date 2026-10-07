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
        // Base ocean green effect
        gl_FragColor *= effectColor * 1.2;
        gl_FragColor.g *= 1.3;  // Enhance green
        gl_FragColor.b *= 1.2;  // Enhance blue for teal tone
        
        // Ocean green glimmering particles
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.0045; 
        float sparkleIntensity = 0.85;
        
        // Wave-like shimmer effect
        float waveFactor = sin(uv.y * 20.0 + u_Time * 3.0) * 0.05;
        uv.x += waveFactor;
        
        // Add sparkle points with ocean-like pattern
        for (int i = 0; i < 4; i++) {
            float timeOffset = float(i) * 1.5;
            float scale = 18.0 + float(i) * 24.0;
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with water-like movement
            float sparkle = r * sin(u_Time * (2.5 + r * 2.0) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 3.0) * sparkleIntensity;
            
            if (sparkle > 0.3) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Fade toward edges
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.6);
                    
                    // Add ocean green sparkle colors (teal/aqua with hints of cyan)
                    gl_FragColor.rgb += vec3(0.2, 1.3, 1.1) * sparkle * fade * 1.5;
                }
            }
        }
        
        // Add pulsing glow for underwater effect
        float glowPulse = 0.1 * sin(u_Time * 1.8) + 0.1;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add subtle color shifting between green and blue for ocean-like effect
        float colorShift = sin(u_Time * 1.5) * 0.07 + 0.07;
        gl_FragColor.g += colorShift * 0.6;
        gl_FragColor.b += colorShift * 0.9;
        
        // Enhance brightness slightly
        gl_FragColor.rgb *= 1.1;
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 