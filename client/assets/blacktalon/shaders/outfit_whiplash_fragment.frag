uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Whiplash parameters
float blueGlowSpeed = 3.0; // Speed of blue glow pulsing
float blueGlowIntensity = 0.2; // Intensity of blue glow
float trailIntensity = 0.15; // Intensity of the fading trail

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
    
    // Create blue whiplash effect
    // Calculate vertical position in texture (0 at bottom, 1 at top)
    float vertPos = v_TexCoord.y;
    
    // Create pulsing effect that travels upward
    float whipPhase = fract(u_Time * blueGlowSpeed);
    float pulseHeight = 0.3; // Height of the pulse
    
    // Calculate distance from the pulse center (traveling upward)
    float distFromPulse = abs(vertPos - whipPhase);
    float pulseMask = smoothstep(pulseHeight, 0.0, distFromPulse);
    
    // Add blue glow that follows the whiplash motion
    vec3 blueGlow = vec3(0.2, 0.4, 1.0) * pulseMask * blueGlowIntensity;
    
    // Add bright white flash at the snapping point
    float snapPhase = fract(u_Time * blueGlowSpeed * 0.33); // Slower than the glow
    float snapFlash = 0.0;
    
    // Flash appears only briefly at the beginning of the cycle
    if (snapPhase < 0.2) {
        snapFlash = (0.2 - snapPhase) * 5.0; // Fade out over 0.2 time units
        snapFlash = snapFlash * snapFlash; // Quadratic falloff for more natural look
    }
    
    // Add the blue glow and white flash
    baseColor.rgb += blueGlow;
    baseColor.rgb += vec3(1.0, 1.0, 1.0) * snapFlash * 0.3;
    
    // Add subtle blue tint overall
    baseColor.rgb = mix(baseColor.rgb, vec3(0.4, 0.6, 1.0), trailIntensity);
    
    // Set output color
    gl_FragColor = baseColor;
} 