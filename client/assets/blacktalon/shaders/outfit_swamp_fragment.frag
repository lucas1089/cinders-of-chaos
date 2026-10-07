uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Swamp parameters
float swampColorIntensity = 0.5; // Intensity of swamp coloring
float swampGlowIntensity = 0.25; // Intensity of swamp glow
float bubbleIntensity = 0.15; // Intensity of swamp bubbles

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
    
    // Extract data from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float cycleFraction = v_TexCoord3.y;
    
    // Create swamp color
    // Base swamp color (murky green-brown)
    vec3 swampColor1 = vec3(0.2, 0.3, 0.1); // Dark murky green
    vec3 swampColor2 = vec3(0.1, 0.2, 0.05); // Even darker green
    
    // Mix colors based on gooey pattern
    float swampPattern = sin(v_TexCoord.x * 10.0 + v_TexCoord.y * 8.0 + u_Time * 0.3) * 0.5 + 0.5;
    vec3 swampColor = mix(swampColor1, swampColor2, swampPattern);
    
    // Apply swamp color to base
    baseColor.rgb = mix(baseColor.rgb, swampColor, swampColorIntensity);
    
    // Create bubbles effect for swamp
    // Random bubble positions that slowly move upward
    float bubbleScale = 30.0;
    float bubbleX = v_TexCoord.x * bubbleScale;
    float bubbleY = v_TexCoord.y * bubbleScale - u_Time * 0.1; // Very slow upward drift
    
    // Create bubble pattern
    float bubbles = sin(bubbleX) * sin(bubbleY) * 0.5 + 0.5;
    bubbles = pow(bubbles, 20.0); // Make bubbles small and distinct
    
    // Add bubbles (brighter green spots)
    vec3 bubbleColor = vec3(0.3, 0.5, 0.2); // Brighter green for bubbles
    baseColor.rgb += bubbleColor * bubbles * bubbleIntensity;
    
    // Add special effects based on current cycle (spin vs dash)
    if (cycleFraction < 0.5) {
        // During spin: add a greenish glow that intensifies with spin
        float spinPhase = cycleFraction * 2.0; // 0 to 1 during spin
        float spinIntensity = sin(spinPhase * 3.14159); // Peaks in middle
        
        // Add glow with spin
        vec3 spinGlow = vec3(0.2, 0.4, 0.1) * spinIntensity * swampGlowIntensity;
        baseColor.rgb += spinGlow;
    } else {
        // During dash: add trails in dash direction
        float dashPhase = (cycleFraction - 0.5) * 2.0; // 0 to 1 during dash
        
        // More intense at beginning of dash
        float dashIntensity = 0.0;
        if (dashPhase < 0.3) {
            dashIntensity = (0.3 - dashPhase) / 0.3; // 1 to 0 during initial dash
        }
        
        // Add trailing effect (dark greenish-black trails)
        vec3 dashColor = vec3(0.05, 0.1, 0.03) * dashIntensity * 0.5;
        baseColor.rgb = mix(baseColor.rgb, dashColor, dashIntensity * 0.3);
        
        // Add glow along leading edge of dash
        if (dashPhase < 0.1) {
            baseColor.rgb += vec3(0.3, 0.5, 0.2) * (0.1 - dashPhase) * 10.0 * 0.2;
        }
    }
    
    // Add edge darkening for more swampy feel
    float edgeDarkening = smoothstep(0.0, 0.7, distFromCenter);
    baseColor.rgb *= 1.0 - edgeDarkening * 0.2;
    
    // Set output color
    gl_FragColor = baseColor;
}