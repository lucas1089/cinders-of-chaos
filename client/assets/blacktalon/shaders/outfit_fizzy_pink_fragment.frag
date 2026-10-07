uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Fizzy Pink parameters
float fizzyIntensity = 0.7; // Intensity of fizzy effect
float pulseFrequency = 0.8; // Frequency of pulsation
float stripCount = 12.0; // Number of color strips

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
    
    // Get distortion value and distance from center
    float distortion = v_TexCoord3.x; // 0 to 1 range
    float distFromCenter = v_TexCoord3.y;
    
    // Create global pulsation effect
    float pulse = sin(u_Time * pulseFrequency) * 0.5 + 0.5;
    
    // Create multi-directional strip pattern
    float stripPattern = 0.0;
    
    // Create strips in multiple directions
    for(float i = 0.0; i < stripCount; i++) {
        // Calculate angle for this direction
        float stripAngle = i * 3.14159 * 2.0 / stripCount;
        
        // Create normalized direction vector
        vec2 stripDir = vec2(cos(stripAngle), sin(stripAngle));
        
        // Project texture coordinate onto this direction
        float projTex = dot(v_TexCoord * 2.0 - 1.0, stripDir) * 0.5 + 0.5;
        
        // Create moving strip pattern
        float stripPhase = i / stripCount; // Phase offset per direction
        float stripSpeed = 0.2 + i * 0.1; // Different speed per direction
        float strip = fract(projTex * 3.0 - u_Time * stripSpeed + stripPhase);
        
        // Create smoother strip with falloff
        strip = smoothstep(0.4, 0.6, strip) - smoothstep(0.6, 0.8, strip);
        
        // Add this strip's contribution
        stripPattern += strip;
    }
    
    // Normalize strip pattern
    stripPattern = stripPattern / stripCount * 2.5; // Boost a bit for more visible stripes
    
    // Create pink color palette for fizzy effect
    vec3 darkPink = vec3(0.7, 0.1, 0.5); // Dark pink
    vec3 midPink = vec3(1.0, 0.4, 0.8);  // Medium pink
    vec3 lightPink = vec3(1.0, 0.7, 0.9); // Light pink
    
    // Mix colors based on distortion value, strip pattern, and pulse
    vec3 color1 = mix(darkPink, midPink, pulse);
    vec3 color2 = mix(midPink, lightPink, 1.0 - pulse);
    vec3 fizzyColor = mix(color1, color2, stripPattern);
    
    // Apply fizzy strips effect with varying intensity
    float effectStrength = fizzyIntensity * (0.7 + 0.3 * pulse);
    
    // Combine distortion value with strip pattern
    float combinedEffect = distortion * 0.7 + stripPattern * 0.3;
    
    // Apply the effect with distance modulation (more at edges)
    baseColor.rgb = mix(baseColor.rgb, fizzyColor, combinedEffect * effectStrength);
    
    // Add extra sparkle along the strips
    float sparklePattern = sin(v_TexCoord.x * 20.0 + v_TexCoord.y * 15.0 + u_Time * 5.0);
    float sparkle = smoothstep(0.7, 0.9, sparklePattern) * stripPattern;
    baseColor.rgb += lightPink * sparkle * pulse * 0.3;
    
    // Add overall glow based on pulse
    baseColor.rgb += midPink * pulse * distFromCenter * 0.1;
    
    // Set output color
    gl_FragColor = baseColor;
} 