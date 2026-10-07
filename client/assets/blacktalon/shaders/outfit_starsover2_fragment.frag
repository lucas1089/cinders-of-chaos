uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform float u_Time;

// Effect parameters - increased for more vibrant effect
float starsIntensity = 2.5;
float overtextureIntensity = 2.0;
float pulseSpeed = 1.2;
float pulseRange = 0.25;
float floatingSpeed = 0.5;

void main()
{
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Create floating effect for texture coordinates
    vec2 floatingCoords = v_TexCoord3;
    floatingCoords.x += sin(u_Time * floatingSpeed + floatingCoords.y * 3.0) * 0.03;
    floatingCoords.y += cos(u_Time * floatingSpeed * 0.7 + floatingCoords.x * 2.0) * 0.03;
    
    vec4 starsEffect = texture2D(u_Tex1, floatingCoords);
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
        // Create gentle pulsing effect
        float pulse = sin(u_Time * pulseSpeed) * pulseRange + 1.0;
        
        // Create blended effect with more emphasis on the texture
        vec3 combinedEffect = mix(
            starsEffect.rgb * starsIntensity,
            overtextureEffect.rgb * overtextureIntensity,
            sin(u_Time * 0.3) * 0.3 + 0.7  // Keep more of the overtexture
        );
        
        // Add color variation and brightness
        float hueShift = sin(u_Time * 0.5) * 0.15;
        combinedEffect.r += hueShift;
        combinedEffect.g += cos(u_Time * 0.6) * 0.1;
        combinedEffect.b += sin(u_Time * 0.7) * 0.12;
        
        // Brighten the effect to avoid darkening
        combinedEffect = max(combinedEffect, vec3(0.9));
        
        // Apply combined effect with additive component to avoid darkening
        gl_FragColor.rgb = baseColor.rgb * 0.4 + combinedEffect * pulse * 0.8;
        
        // Add floating sparkles
        float sparkles = fract(sin(dot(v_TexCoord, vec2(12.9898, 78.233) + u_Time)) * 43758.5453);
        sparkles = pow(sparkles, 20.0) * 1.5;
        gl_FragColor.rgb += vec3(sparkles);
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 