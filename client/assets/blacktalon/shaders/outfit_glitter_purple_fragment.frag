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
        // Base purple effect - rich purple base
        gl_FragColor *= effectColor * 1.2;
        gl_FragColor.r *= 1.2;  // Enhance red for richer purple
        gl_FragColor.b *= 1.4;  // Enhance blue for vibrant purple
        
        // Purple glimmering particles
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.0055; // Slightly larger sparkles for mystical effect
        float sparkleIntensity = 0.95; // Higher intensity for magical feel
        
        // Spiral-like shimmer effect
        float spiral = length(uv - vec2(0.5));
        float spiralFactor = sin(spiral * 10.0 - u_Time * 2.0) * 0.03;
        uv += vec2(spiralFactor);
        
        // Add sparkle points with mystical pattern
        for (int i = 0; i < 5; i++) {
            float timeOffset = float(i) * 1.3;
            float scale = 19.0 + float(i) * 20.0;
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with magical pulsing
            float sparkle = r * sin(u_Time * (2.8 + r * 3.0) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 2.7) * sparkleIntensity;
            
            if (sparkle > 0.25) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Mystical fade toward edges
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.4);
                    
                    // Add purple sparkle variations (purple with hints of magenta and blue)
                    vec3 sparkleColor;
                    if (r < 0.33) {
                        sparkleColor = vec3(0.9, 0.3, 1.5); // Purple-magenta
                    } else if (r < 0.66) {
                        sparkleColor = vec3(0.6, 0.1, 1.7); // Deep purple
                    } else {
                        sparkleColor = vec3(1.0, 0.4, 1.2); // Lighter purple-pink
                    }
                    
                    gl_FragColor.rgb += sparkleColor * sparkle * fade * 1.6;
                }
            }
        }
        
        // Add pulsing glow for mystical effect
        float glowPulse = 0.15 * sin(u_Time * 1.6) + 0.15;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add subtle color shifting between purple and magenta
        float colorShift = sin(u_Time * 1.7) * 0.09 + 0.09;
        gl_FragColor.r += colorShift * 0.7;
        gl_FragColor.b += colorShift * 0.5;
        
        // Enhance brightness for magical shine
        gl_FragColor.rgb *= 1.15;
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 