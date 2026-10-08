uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Cursed parameters
float crackIntensity = 0.4; // Intensity of cracks
float redGlowIntensity = 0.3; // Intensity of red glow
float darkPulseIntensity = 0.2; // Intensity of dark pulsing

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample texture with normal coordinates
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Get glitch zone and time from vertex shader
    float glitchZone = v_TexCoord3.x;
    float time = v_TexCoord3.y;
    
    // Create dark base with reddish tint
    vec3 cursedBase = mix(baseColor.rgb, vec3(0.2, 0.02, 0.05), 0.5);
    
    // Add pulsing darkness
    float darkPulse = sin(time * 0.8) * 0.5 + 0.5;
    cursedBase = mix(cursedBase, vec3(0.1, 0.0, 0.0), darkPulse * darkPulseIntensity);
    
    // Create cracks pattern
    vec2 centeredCoord = v_TexCoord - vec2(0.5, 0.5);
    float crackPattern = sin(centeredCoord.x * 40.0) * sin(centeredCoord.y * 40.0);
    crackPattern = smoothstep(0.9, 1.0, abs(crackPattern));
    
    // Make cracks move and animate
    float animatedCracks = fract(crackPattern + time * 0.05);
    animatedCracks = smoothstep(0.4, 0.5, animatedCracks);
    
    // Create pulsing red glow for the cracks
    float redPulse = sin(time * 0.6) * 0.5 + 0.5;
    vec3 crackColor = mix(vec3(1.0, 0.0, 0.0), vec3(0.7, 0.0, 0.0), redPulse);
    
    // Apply cracks
    vec3 withCracks = mix(cursedBase, crackColor, animatedCracks * crackIntensity);
    
    // Add red glow to areas affected by glitch
    vec3 withGlow = mix(withCracks, vec3(0.5, 0.0, 0.0), glitchZone * redGlowIntensity);
    
    // Add flickering effect
    float flicker = step(0.95, fract(time * 3.0));
    withGlow = mix(withGlow, vec3(0.6, 0.0, 0.0), flicker * glitchZone * 0.3);
    
    // Create noise-like dark spots
    float noisePattern = fract(sin(v_TexCoord.x * 100.0 + v_TexCoord.y * 50.0 + time) * 5000.0);
    float darkSpots = step(0.7, noisePattern) * step(0.5, glitchZone);
    
    // Apply dark spots
    vec3 finalColor = mix(withGlow, vec3(0.0, 0.0, 0.0), darkSpots * 0.5);
    
    // Set output color
    gl_FragColor = vec4(finalColor, baseColor.a);
} 