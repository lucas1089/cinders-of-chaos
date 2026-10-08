uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Fixed jumping parameters
float windIntensity = 0.2; // Intensity of wind effect
float dustIntensity = 0.3; // Intensity of dust at landing

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
    
    // Get jump phase and curve from vertex shader
    float jumpPhase = v_TexCoord3.x;
    float jumpCurve = v_TexCoord3.y;
    
    // Add wind trail effect during upward and downward movement (faster = more trail)
    if (jumpPhase < 0.45 || jumpPhase > 0.55) {
        // Stronger at mid-jump, lighter near ground
        float windStrength;
        
        if (jumpPhase < 0.45) {
            // Going up - wind increases as we go up
            windStrength = jumpPhase / 0.45; // 0 to 1 during ascent
        } else {
            // Coming down - wind increases as we go faster
            windStrength = (1.0 - jumpPhase) / 0.45; // 1 to 0 during descent, but reversed
        }
        
        // Create horizontal wind trail on sides of character
        float horizontalPos = v_TexCoord.x * 2.0 - 1.0; // -1 to 1
        float windTrail = 0.0;
        
        // Left side wind
        if (horizontalPos < -0.3) {
            windTrail = smoothstep(-1.0, -0.3, horizontalPos) * 0.5;
        }
        
        // Right side wind
        if (horizontalPos > 0.3) {
            windTrail = smoothstep(1.0, 0.3, horizontalPos) * 0.5;
        }
        
        // Apply wind effect with proper strength
        vec3 windColor = vec3(0.9, 0.9, 1.0); // Slight blue tint for wind
        baseColor.rgb = mix(baseColor.rgb, windColor, windTrail * windStrength * windIntensity);
    }
    
    // Add dust effect at landing
    if (jumpPhase > 0.9 || jumpPhase < 0.1) {
        // Only at the bottom of the sprite
        if(v_TexCoord.y > 0.7) {
            // Calculate dust amount
            float dustPhase;
            if(jumpPhase < 0.1) {
                dustPhase = 1.0 - (jumpPhase / 0.1); // 1 to 0 as we leave the ground
            } else {
                dustPhase = (jumpPhase - 0.9) / 0.1; // 0 to 1 as we hit the ground
            }
            
            // Create dust pattern at bottom
            float dustX = v_TexCoord.x * 10.0 + u_Time * 5.0;
            float dustY = v_TexCoord.y * 4.0;
            float dust = sin(dustX) * sin(dustY) * 0.5 + 0.5;
            dust = smoothstep(0.4, 0.6, dust);
            
            // Apply dust effect
            vec3 dustColor = vec3(0.8, 0.7, 0.6); // Brownish dust
            baseColor.rgb = mix(baseColor.rgb, dustColor, dust * dustPhase * dustIntensity);
        }
    }
    
    // Add slight brightening at peak of jump (like sun hitting at top)
    if (jumpPhase > 0.4 && jumpPhase < 0.6) {
        float peakPhase = 1.0 - abs(jumpPhase - 0.5) * 10.0; // 0 to 1 at peak
        baseColor.rgb *= 1.0 + peakPhase * 0.1; // Slight brightness increase at peak
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 