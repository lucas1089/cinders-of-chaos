uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Plasmic Ocean parameters
float oceanIntensity = 0.7; // Intensity of ocean effect
float bubbleFrequency = 0.5; // Frequency of bubble formations
float bubbleCount = 5.0; // Number of bubbles

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
    
    // Get wave distortion and distance from center
    float waveDistortion = v_TexCoord3.x;
    float distFromCenter = v_TexCoord3.y;
    
    // Create a subtle wave/flow pattern
    float flowPattern = waveDistortion * 0.5 + 0.5; // 0 to 1 range
    
    // Add rippling water surface effect
    float waterSurface = sin(v_TexCoord.x * 15.0 + v_TexCoord.y * 10.0 + u_Time * 0.8);
    waterSurface = waterSurface * 0.5 + 0.5; // 0 to 1 range
    
    // Create bubble effect - floating upward
    float bubbles = 0.0;
    for(float i = 0.0; i < bubbleCount; i++) {
        // Each bubble has a different starting position and speed
        float bubbleSeed = i / bubbleCount;
        
        // Bubble positions - move upward
        float bubbleX = sin(bubbleSeed * 6.28 + u_Time * (0.2 + bubbleSeed * 0.3)) * 0.6;
        float bubbleY = fract(bubbleSeed - u_Time * (0.2 + bubbleSeed * 0.1)) * 2.0 - 1.0; // Move up and wrap
        
        // Center the bubbles around character
        bubbleX = bubbleX * 0.5 + 0.5; // 0 to 1 range
        bubbleY = bubbleY * 0.5 + 0.5; // 0 to 1 range
        
        // Calculate distance to bubble
        float bubbleDist = distance(vec2(bubbleX, bubbleY), v_TexCoord);
        
        // Create bubble with size variation
        float bubbleSize = 0.02 + bubbleSeed * 0.02; // Varied sizes
        float bubble = smoothstep(bubbleSize, 0.0, bubbleDist);
        
        // Apply bubble size pulsation
        float pulsation = sin(u_Time * 2.0 + bubbleSeed * 6.28) * 0.5 + 0.5;
        bubble *= 0.7 + pulsation * 0.3;
        
        // Add this bubble to total
        bubbles += bubble;
    }
    
    // Ocean color palette - deep to light
    vec3 deepColor = vec3(0.0, 0.1, 0.4); // Deep ocean blue
    vec3 midColor = vec3(0.1, 0.3, 0.7);  // Mid-water blue
    vec3 lightColor = vec3(0.4, 0.7, 0.9); // Light surface blue
    vec3 foamColor = vec3(0.8, 0.9, 1.0);  // White foam/bubble color
    
    // Create main ocean color based on flow pattern and waves
    vec3 oceanColor;
    if(flowPattern > 0.7) {
        // Lighter areas
        oceanColor = mix(midColor, lightColor, (flowPattern - 0.7) / 0.3);
    } else {
        // Deeper areas
        oceanColor = mix(deepColor, midColor, flowPattern / 0.7);
    }
    
    // Add water surface highlights
    oceanColor = mix(oceanColor, lightColor, waterSurface * 0.2);
    
    // Create submarine light effect - fluctuating glow
    float lightEffect = sin(u_Time * 0.2) * 0.5 + 0.5; // Slow pulsing
    vec3 lightGlow = mix(deepColor, lightColor, lightEffect);
    
    // Apply ocean colors to base
    baseColor.rgb = mix(baseColor.rgb, oceanColor, oceanIntensity * (0.5 + distFromCenter * 0.5));
    
    // Add subtle light rays effect
    float rays = sin(v_TexCoord.x * 5.0 + u_Time * 0.3) * 0.5 + 0.5;
    rays *= (1.0 - v_TexCoord.y); // More at top
    baseColor.rgb = mix(baseColor.rgb, lightGlow, rays * 0.15);
    
    // Add bubbles
    baseColor.rgb = mix(baseColor.rgb, foamColor, bubbles * 0.7);
    
    // Add overall water glow/sheen
    baseColor.rgb += lightColor * flowPattern * 0.1 * (0.8 + lightEffect * 0.2);
    
    // Set output color
    gl_FragColor = baseColor;
} 