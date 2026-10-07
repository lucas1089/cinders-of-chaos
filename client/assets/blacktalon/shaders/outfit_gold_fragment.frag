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
        // Base gold effect - moderate saturation
        gl_FragColor *= effectColor * 1.15;
        
        // Balanced glimmering particles
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.006; // Medium-sized sparkles
        float sparkleIntensity = 0.8; // Moderate intensity sparkles
        
        // Add sparkle points with balanced frequencies
        for (int i = 0; i < 4; i++) { // 4 types of sparkles
            float timeOffset = float(i) * 1.0;
            float scale = 18.0 + float(i) * 25.0;
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with moderate drama
            float sparkle = r * sin(u_Time * (3.5 + r * 3.0) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 4.0) * sparkleIntensity;
            
            // Balanced threshold for sparkle visibility
            if (sparkle > 0.3) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Medium fade toward edges
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.7);
                    
                    // Add moderately bright sparkle to fragment color
                    gl_FragColor.rgb += vec3(1.1, 1.0, 0.6) * sparkle * fade * 1.5;
                }
            }
        }
        
        // Add moderate pulsing glow
        float glowPulse = 0.1 * sin(u_Time * 2.5) + 0.1;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add gentle color shifting for subtle sparkle
        float colorShift = sin(u_Time * 2.0) * 0.07 + 0.07;
        gl_FragColor.r += colorShift;
        gl_FragColor.g += colorShift * 0.8;
        
        // Enhance brightness moderately
        gl_FragColor.rgb *= 1.1;
    }
    
    if(gl_FragColor.a < 0.01) discard;
}