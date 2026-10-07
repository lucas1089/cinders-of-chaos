uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_Position;
varying float v_Time;

// Pseudo-random function for glitter effect
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main()
{
    gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    if(texcolor.a > 0.1) {
        // Golden base color with slight pulsing
        float pulse = 0.15 * sin(u_Time * 1.5) + 0.85;
        vec3 goldBaseColor = vec3(1.0, 0.84, 0.2) * pulse;
        
        // Apply gold base color
        gl_FragColor.rgb = mix(gl_FragColor.rgb, goldBaseColor, 0.5);
        
        // Add floating gold particles
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.008; // Size of sparkles
        float sparkleIntensity = 1.0; // Brightness of sparkles
        
        // Multiple layers of sparkles
        for (int i = 0; i < 4; i++) {
            float timeOffset = float(i) * 1.5;
            float scale = 15.0 + float(i) * 20.0;
            
            // Create grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with smooth animation
            float sparkle = r * sin(u_Time * (2.0 + r * 2.0) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 3.0) * sparkleIntensity;
            
            // Only show sparkles above threshold
            if (sparkle > 0.2) {
                // Distance from current fragment to center of sparkle
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if close to center
                if (dist < sparkleSize) {
                    // Smooth fade toward edges
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 2.0);
                    
                    // Add gold sparkle with slight color variation
                    float colorVar = sin(r * 6.28 + u_Time) * 0.1 + 0.9;
                    vec3 sparkleColor = vec3(1.0, 0.9 * colorVar, 0.4 * colorVar);
                    gl_FragColor.rgb += sparkleColor * sparkle * fade * 1.5;
                }
            }
        }
        
        // Add larger floating particles from texture coordinates
        float floatPulse = 0.5 + 0.5 * sin(v_TexCoord3.y * 10.0 + u_Time * 2.0);
        vec3 floatColor = vec3(1.0, 0.95, 0.6) * floatPulse * 0.3;
        gl_FragColor.rgb += floatColor * texcolor.a;
        
        // Add subtle glow
        float glowPulse = 0.1 * sin(u_Time * 1.8) + 0.1;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Enhance brightness
        gl_FragColor.rgb *= 1.1;
    }
    
    // Apply UI element's color
    gl_FragColor *= u_Color;
    
    if(gl_FragColor.a < 0.01) discard;
} 