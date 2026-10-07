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
        // Base fire effect - red/orange with slight yellow tint
        gl_FragColor *= effectColor * 1.25;
        gl_FragColor.r *= 1.6;  // Enhance red
        gl_FragColor.g *= 0.9;  // Reduce green slightly
        gl_FragColor.b *= 0.4;  // Reduce blue significantly
        
        // Get approximate texture size from texcoord deltas
        vec2 dx = dFdx(v_TexCoord * 256.0);
        vec2 dy = dFdy(v_TexCoord * 256.0);
        float texSize = max(length(dx), length(dy));
        float sizeScale = 32.0 / texSize; // Scale relative to 32x32 textures
        
        // Fire glimmering particles
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.0035 * sizeScale; // Smaller sparkles for fire
        float sparkleIntensity = 1.0; // Higher intensity for fire particles
        
        // Add sparkle points with balanced frequencies
        for (int i = 0; i < 7; i++) { // More types of sparkles for denser fire particles
            float timeOffset = float(i) * 1.1;
            float scale = (25.0 + float(i) * 24.0) / sizeScale; // Scale grid size inversely to texture size
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with more dramatic effect
            float sparkle = r * sin(u_Time * (3.0 + r * 2.5) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 3.2) * sparkleIntensity; // Less power for more visible particles
            
            // Lower threshold for sparkle visibility to show more particles
            if (sparkle > 0.2) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Strong fade toward edges for crisp particles
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.4); // Less power for softer edges
                    
                    // Add fire-colored sparkle to fragment color (red/orange)
                    gl_FragColor.rgb += vec3(1.9, 0.8, 0.3) * sparkle * fade * 1.7;
                }
            }
        }
        
        // Add pulsing glow for fire effect
        float glowPulse = 0.14 * sin(u_Time * 3.0) + 0.14;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add subtle color shifting between red and orange for dynamic flame effect
        float colorShift = sin(u_Time * 2.2) * 0.1 + 0.1;
        gl_FragColor.r += colorShift * 0.3;
        gl_FragColor.g += colorShift * 0.2;
        
        // Enhance brightness for fire shine
        gl_FragColor.rgb *= 1.2;
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 