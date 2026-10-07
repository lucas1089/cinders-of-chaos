uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Jumping fragment parameters
float windEffectIntensity = 0.1; // Intensity of wind effect during jump
float landingDustIntensity = 0.3; // Intensity of dust effect on landing
float peakGlowIntensity = 0.2; // Intensity of glow at the peak

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
    
    // Extract jump info from vertex shader
    float jumpPhase = v_TexCoord3.x; // 0 to 1 for jump cycle
    float jumpCurve = v_TexCoord3.y; // Height curve (0 at ground, 1 at peak)
    
    // Add wind trail effect during ascent and descent
    // This adds slightly brighter streaks on the sides when jumping or falling
    if (jumpPhase < 0.4 || (jumpPhase > 0.6 && jumpPhase < 0.9)) {
        // Add trailing effect when going up or coming down
        float windEffect = 0.0;
        
        // Calculate horizontal position within texture (0 at left, 1 at right)
        float horizPos = v_TexCoord.x;
        
        // Create wind trail on left side during ascent
        if (jumpPhase < 0.4 && horizPos < 0.4) {
            windEffect = (0.4 - horizPos) * 2.5; // Stronger near left edge
            windEffect *= (0.4 - jumpPhase) * 2.5; // Fades as we reach peak
        }
        
        // Create wind trail on right side during descent
        if (jumpPhase > 0.6 && jumpPhase < 0.9 && horizPos > 0.6) {
            windEffect = (horizPos - 0.6) * 2.5; // Stronger near right edge
            windEffect *= (jumpPhase - 0.6) * 3.3; // Increases as we fall
            windEffect *= (0.9 - jumpPhase) * 10.0; // But fades near landing
        }
        
        // Apply wind effect - subtle bright streaks
        baseColor.rgb += vec3(0.4, 0.4, 0.5) * windEffect * windEffectIntensity;
    }
    
    // Add dust effect when landing
    if (jumpPhase > 0.9 || jumpPhase < 0.1) {
        // Calculate vertical position in texture (0 at top, 1 at bottom)
        float vertPos = v_TexCoord.y;
        
        // Only apply dust at the bottom part of the sprite
        if (vertPos > 0.7) {
            float dustAmount = 0.0;
            
            // Dust when landing (phase approaching 1)
            if (jumpPhase > 0.9) {
                dustAmount = (jumpPhase - 0.9) * 10.0; // 0 to 1 during landing
            }
            
            // Dust lingering after landing (phase starting from 0)
            if (jumpPhase < 0.1) {
                dustAmount = (0.1 - jumpPhase) * 10.0; // 1 to 0 after landing
            }
            
            // Create a dust pattern with noise-like effect
            float dustX = v_TexCoord.x * 10.0; 
            float dustY = vertPos * 5.0;
            float dustPattern = sin(dustX) * sin(dustY) * 0.5 + 0.5;
            dustPattern = smoothstep(0.4, 0.6, dustPattern);
            
            // Apply dust effect - slightly brownish clouds at the bottom
            vec3 dustColor = vec3(0.6, 0.5, 0.4);
            baseColor.rgb = mix(baseColor.rgb, dustColor, dustPattern * dustAmount * landingDustIntensity);
        }
    }
    
    // Add slight glow at the peak of the jump
    if (jumpPhase > 0.45 && jumpPhase < 0.55) {
        // Calculate glow intensity, peaking at phase 0.5
        float peakPhase = 1.0 - abs(jumpPhase - 0.5) * 20.0; // 0 to 1 at peak
        
        // Apply subtle white glow
        baseColor.rgb += vec3(1.0) * peakPhase * peakGlowIntensity;
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 