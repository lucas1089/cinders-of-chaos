uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform float u_Time;

// Effect parameters
float starsIntensity = 2.0;
float overtextureIntensity = 1.5;
float pulseSpeed = 1.8;
float pulseRange = 0.3;

void main()
{
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 starsEffect = texture2D(u_Tex1, v_TexCoord3);
    vec4 overtextureEffect = texture2D(u_Tex2, v_TexCoord4);
    
    // Apply color based on outfit parts
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Set initial output color
    gl_FragColor = baseColor;
    
    if(texcolor.a > 0.9) {
        // Create pulsing effect
        float pulse = sin(u_Time * pulseSpeed) * pulseRange + 1.0;
        
        // Create blended effect
        vec3 combinedEffect = mix(
            starsEffect.rgb * starsIntensity,
            overtextureEffect.rgb * overtextureIntensity,
            sin(u_Time * 0.5) * 0.5 + 0.5  // Oscillate between effects
        );
        
        // Add color variation
        float hueShift = sin(u_Time * 0.7) * 0.1;
        combinedEffect.r += hueShift;
        combinedEffect.b += hueShift * 0.5;
        
        // Apply combined effect with pulse
        gl_FragColor.rgb = baseColor.rgb * combinedEffect * pulse;
        
        // Add sparkle highlights at peak pulse times
        float sparkleTime = mod(u_Time, 3.0);
        if(sparkleTime < 0.2) {
            float sparkleIntensity = (0.2 - sparkleTime) * 5.0;
            gl_FragColor.rgb += starsEffect.rgb * sparkleIntensity;
        }
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 