uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying float v_Time;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Pseudo-random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// HSV to RGB conversion
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main()
{
    gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 effectColor = texture2D(u_Tex1, v_TexCoord3);
    
    if(texcolor.a > 0.9) {
        // Base color effect with rainbow cycling
        float cycleTime = mod(u_Time, 3600.0);
        float rainbowSpeed = 2.0;
        
        // Trippy color cycling base
        vec3 rainbowColor = hsv2rgb(vec3(
            mod(cycleTime * 0.3, 1.0), // Hue cycles through rainbow
            0.8 + 0.2 * sin(cycleTime * 0.5), // Saturation pulses
            0.9 + 0.1 * cos(cycleTime * 0.7)  // Value/brightness pulses
        ));
        
        // Mix the rainbow color with the texture
        gl_FragColor *= effectColor * 1.5;
        gl_FragColor.rgb *= rainbowColor * 1.3;
        
        // Insane glimmering particles
        vec2 uv = v_TexCoord;
        float sparkleSize = 0.006 + 0.002 * sin(cycleTime * 1.5); // Pulsing sparkle size
        float sparkleIntensity = 1.2; // High intensity glitter
        
        // Fractal movement for uv coordinates
        float fractalX = sin(uv.y * 7.0 + cycleTime * 3.0) * 0.03;
        float fractalY = cos(uv.x * 8.0 + cycleTime * 2.5) * 0.03;
        uv += vec2(fractalX, fractalY);
        
        // Add multi-layered sparkle points
        for (int i = 0; i < 7; i++) { // More layers of sparkles
            float timeOffset = float(i) * 1.1;
            float scale = 15.0 + float(i) * 20.0;
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with trippy timing
            float sparkle = r * sin(cycleTime * (2.0 + r * 2.5) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 2.2) * sparkleIntensity;
            
            if (sparkle > 0.2) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Sharp fade toward edges
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.3);
                    
                    // Add rainbow-colored sparkles that cycle through hues
                    vec3 sparkleColor = hsv2rgb(vec3(
                        mod(r + cycleTime * 0.2, 1.0), // Each sparkle has its own cycling hue
                        0.9,
                        1.0
                    ));
                    
                    gl_FragColor.rgb += sparkleColor * sparkle * fade * 2.0;
                }
            }
        }
        
        // Add kaleidoscopic effect
        float kaleidoTime = cycleTime * 0.5;
        vec2 kaleidoUV = uv - 0.5;
        float kaleidoAngle = atan(kaleidoUV.y, kaleidoUV.x);
        float kaleidoRadius = length(kaleidoUV);
        
        // Create rippling effect
        float ripple = sin(kaleidoRadius * 20.0 - kaleidoTime * 3.0) * 0.1;
        gl_FragColor.rgb += ripple * vec3(0.5, 0.8, 1.0);
        
        // Add pulsing glow
        float glowPulse = 0.2 * sin(cycleTime * 3.5) + 0.2;
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add color shifting
        float colorShift = sin(cycleTime * 2.3) * 0.1 + 0.1;
        gl_FragColor.r += colorShift * sin(cycleTime * 1.1);
        gl_FragColor.g += colorShift * sin(cycleTime * 1.5 + 2.0);
        gl_FragColor.b += colorShift * sin(cycleTime * 1.7 + 4.0);
        
        // Add oscillating color bands
        float bands = sin(uv.y * 30.0 + cycleTime * 5.0) * 0.1;
        gl_FragColor.rgb += bands * hsv2rgb(vec3(mod(uv.y + cycleTime * 0.1, 1.0), 0.8, 0.8));
        
        // Add color burn effect for extra saturation
        gl_FragColor.rgb = 1.0 - (1.0 - gl_FragColor.rgb) * (1.0 - gl_FragColor.rgb * 0.5);
        
        // Enhance brightness for extreme shine
        gl_FragColor.rgb *= 1.2;
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 