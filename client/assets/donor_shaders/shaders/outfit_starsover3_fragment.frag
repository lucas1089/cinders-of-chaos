uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform float u_Time;

// Effect parameters - colorful flowing effect
float starsIntensity = 2.5;
float overtextureIntensity = 2.2;
float pulseSpeed = 0.8;
float pulseRange = 0.2;
float colorCycleSpeed = 0.3;

void main()
{
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Create flowing effect with multiple waves
    vec2 flowCoords = v_TexCoord3;
    flowCoords.x += sin(u_Time * 0.4 + flowCoords.y * 4.0) * 0.04;
    flowCoords.y += cos(u_Time * 0.3 + flowCoords.x * 3.0) * 0.04;
    
    // Second layer of movement
    flowCoords.x += sin(u_Time * 0.2 + flowCoords.y * 2.0) * 0.02;
    flowCoords.y += cos(u_Time * 0.25 + flowCoords.x * 5.0) * 0.02;
    
    vec4 starsEffect = texture2D(u_Tex1, flowCoords);
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
        // Create smooth pulsing effect
        float pulse = sin(u_Time * pulseSpeed) * pulseRange + 1.0;
        
        // Cycle through colors over time
        vec3 colorCycle;
        colorCycle.r = sin(u_Time * colorCycleSpeed) * 0.5 + 0.5;
        colorCycle.g = sin(u_Time * colorCycleSpeed + 2.1) * 0.5 + 0.5;
        colorCycle.b = sin(u_Time * colorCycleSpeed + 4.2) * 0.5 + 0.5;
        
        // Create blended effect with enhanced colors
        vec3 combinedEffect = mix(
            starsEffect.rgb * starsIntensity,
            overtextureEffect.rgb * overtextureIntensity,
            sin(u_Time * 0.2) * 0.2 + 0.6  // Favor the overtexture
        );
        
        // Apply color cycling and brightness
        combinedEffect *= colorCycle;
        
        // Ensure it stays bright
        combinedEffect = max(combinedEffect, vec3(0.7, 0.7, 0.9));
        
        // Apply combined effect with additive blend to keep it bright
        gl_FragColor.rgb = baseColor.rgb * 0.3 + combinedEffect * pulse * 0.9;
        
        // Add flowing wave effect
        float waves = sin((v_TexCoord.x + v_TexCoord.y) * 20.0 + u_Time * 2.0) * 0.5 + 0.5;
        waves = pow(waves, 5.0) * 0.2;
        gl_FragColor.rgb += colorCycle * waves;
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 