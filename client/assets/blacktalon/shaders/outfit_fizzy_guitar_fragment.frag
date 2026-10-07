uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Fizzy Guitar parameters
float stringIntensity = 0.7; // Intensity of string effect
float musicCycleSpeed = 0.3; // Speed of music pattern cycle
float glowIntensity = 0.4; // Intensity of string glow

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
    
    // Get string information from vertex shader
    float stringPosition = v_TexCoord3.x; // Which string (0 to 1)
    float stringEffect = v_TexCoord3.y; // String effect intensity (0 to 1)
    
    // Create a musical pattern cycle - different notes/beats light up at different times
    float musicPattern = fract(u_Time * musicCycleSpeed);
    
    // Create distinct beats in the cycle
    float beat1 = smoothstep(0.1, 0.0, abs(musicPattern - 0.0));
    float beat2 = smoothstep(0.1, 0.0, abs(musicPattern - 0.25));
    float beat3 = smoothstep(0.1, 0.0, abs(musicPattern - 0.5));
    float beat4 = smoothstep(0.1, 0.0, abs(musicPattern - 0.75));
    
    // Create music pattern - different strings light up at different beats
    // Based on a simple chord progression pattern
    float stringActivation = 0.0;
    
    // String 1 (lowest)
    if(stringPosition < 0.15) {
        stringActivation = beat1 * 0.8 + beat3 * 0.9;
    }
    // String 2
    else if(stringPosition < 0.3) {
        stringActivation = beat2 * 0.7 + beat4 * 0.8;
    }
    // String 3
    else if(stringPosition < 0.45) {
        stringActivation = beat1 * 0.6 + beat3 * 0.7;
    }
    // String 4
    else if(stringPosition < 0.6) {
        stringActivation = beat2 * 0.9 + beat4 * 0.6;
    }
    // String 5
    else if(stringPosition < 0.75) {
        stringActivation = beat1 * 0.7 + beat3 * 0.8;
    }
    // String 6 & 7 (highest)
    else {
        stringActivation = beat2 * 0.8 + beat4 * 0.9;
    }
    
    // Create string color based on position (like guitar strings of different materials/thicknesses)
    vec3 stringColor;
    if(stringPosition < 0.15) {
        // Lowest string - thicker, darker
        stringColor = vec3(0.8, 0.6, 0.3); // Bronze/copper
    } else if(stringPosition < 0.45) {
        // Lower strings - warm tone
        stringColor = vec3(0.9, 0.7, 0.4); // Brass/gold
    } else if(stringPosition < 0.75) {
        // Middle strings - neutral
        stringColor = vec3(0.8, 0.8, 0.8); // Silver
    } else {
        // Highest strings - bright
        stringColor = vec3(0.9, 0.9, 1.0); // Steel/bright silver
    }
    
    // Modulate string color with music activation
    vec3 activeStringColor = mix(stringColor, vec3(1.0), stringActivation * 0.7);
    
    // Apply string color when string effect is active
    float finalStringEffect = stringEffect * (0.3 + stringActivation * 0.7);
    baseColor.rgb = mix(baseColor.rgb, activeStringColor, finalStringEffect * stringIntensity);
    
    // Apply glow around active strings
    float glow = stringEffect * stringActivation * glowIntensity;
    baseColor.rgb += activeStringColor * glow;
    
    // Create beat visual effect at string pluck points
    float beatEffect = (beat1 + beat2 + beat3 + beat4) * 0.25;
    
    // Apply beat highlight effect to full sprite
    float beatHighlight = beatEffect * 0.1;
    baseColor.rgb *= 1.0 + beatHighlight;
    
    // Add special effect when hitting major beats - like stage lights
    if(beatEffect > 0.5) {
        // Create a colored background glow based on current beat
        vec3 beatColor = mix(
            vec3(0.8, 0.2, 0.2), // Red for beat 1/3
            vec3(0.2, 0.2, 0.8), // Blue for beat 2/4
            step(0.3, musicPattern) - step(0.7, musicPattern) // Switch colors based on pattern
        );
        
        // Apply subtle background glow
        baseColor.rgb = mix(baseColor.rgb, beatColor, beatEffect * 0.1);
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 