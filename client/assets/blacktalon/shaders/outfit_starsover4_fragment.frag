uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform float u_Time;

// Effect parameters - dreamy ethereal effect
float starsIntensity = 2.8;
float overtextureIntensity = 2.5;
float waveSpeed = 0.5;
float colorShiftSpeed = 0.4;
float waveAmplitude = 0.05;

void main()
{
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Create ethereal flowing coordinates with spiral movement
    vec2 center = vec2(0.5, 0.5);
    vec2 toCenter = v_TexCoord3 - center;
    float angle = u_Time * 0.15;
    float dist = length(toCenter);
    
    // Spiral coordinates
    vec2 dreamyCoords = v_TexCoord3;
    dreamyCoords.x += sin(u_Time * waveSpeed + dreamyCoords.y * 3.0 + dist * 5.0) * waveAmplitude;
    dreamyCoords.y += cos(u_Time * waveSpeed * 0.8 + dreamyCoords.x * 2.0 + dist * 4.0) * waveAmplitude;
    
    // Add rotation based on distance
    float rotAmount = sin(u_Time * 0.1) * 0.01 + 0.01;
    mat2 rotMat = mat2(cos(rotAmount), -sin(rotAmount), sin(rotAmount), cos(rotAmount));
    dreamyCoords = center + rotMat * (dreamyCoords - center);
    
    vec4 starsEffect = texture2D(u_Tex1, dreamyCoords);
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
        // Create dreamlike color shifting
        vec3 colorShift;
        colorShift.r = sin(u_Time * colorShiftSpeed) * 0.3 + 0.7;
        colorShift.g = sin(u_Time * colorShiftSpeed * 0.7 + 1.5) * 0.3 + 0.7;
        colorShift.b = sin(u_Time * colorShiftSpeed * 1.3 + 3.0) * 0.3 + 0.7;
        
        // Create blended effect with emphasis on brightness
        vec3 combinedEffect = mix(
            starsEffect.rgb * starsIntensity,
            overtextureEffect.rgb * overtextureIntensity,
            sin(u_Time * 0.1) * 0.15 + 0.5  // Gentle transitions
        );
        
        // Apply color shifting and enhancement
        combinedEffect *= colorShift;
        
        // Make sure it's bright and vibrant
        combinedEffect = max(combinedEffect, vec3(0.8, 0.8, 0.9));
        
        // Apply combined effect with additive blending to maintain brightness
        gl_FragColor.rgb = baseColor.rgb * 0.2 + combinedEffect * 0.95;
        
        // Add shimmering effect
        float shimmer = fract(sin(dot(v_TexCoord * 2.5, vec2(12.9898, 78.233) + u_Time * 0.5)) * 43758.5453);
        shimmer = pow(shimmer, 12.0) * 0.5;
        gl_FragColor.rgb += colorShift * shimmer;
        
        // Add gentle radial wave effect
        float radialWave = sin(dist * 15.0 - u_Time * 1.2) * 0.5 + 0.5;
        radialWave = pow(radialWave, 3.0) * 0.15;
        gl_FragColor.rgb += colorShift * radialWave;
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 