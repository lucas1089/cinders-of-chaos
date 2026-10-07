uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Fizzy parameters
float orangeIntensity = 0.25; // Intensity of orange coloring
float fizzyBubbleFrequency = 20.0; // How many small bubbles
float bubbleIntensity = 0.15; // Intensity of bubble highlights
float fizzGlowFrequency = 2.0; // Frequency of the fizz glow

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
    
    // Extract data from v_TexCoord3
    float distFromCenter = v_TexCoord3.x; // Distance from center
    float bubbleStrength = v_TexCoord3.y; // Bubble rising strength
    
    // Create orange fizzy soda effect
    // Mix with orange color
    vec3 orangeColor = vec3(1.0, 0.5, 0.0); // Bright orange
    baseColor.rgb = mix(baseColor.rgb, orangeColor, orangeIntensity);
    
    // Create small fizzy bubbles
    // Use high-frequency noise-like pattern for tiny bubbles
    float bubbleX = v_TexCoord.x * fizzyBubbleFrequency;
    float bubbleY = v_TexCoord.y * fizzyBubbleFrequency - u_Time * 5.0; // Rising bubbles
    float smallBubbles = sin(bubbleX + u_Time * 2.0) * sin(bubbleY) * 0.5 + 0.5;
    smallBubbles = pow(smallBubbles, 8.0); // Make bubbles smaller and more distinct
    
    // Add tiny white bubbles
    baseColor.rgb += vec3(smallBubbles * bubbleIntensity);
    
    // Add larger bubble highlights from vertex shader
    float bubbleHighlight = sin(bubbleStrength * 3.14159) * 0.5 + 0.5;
    bubbleHighlight = pow(bubbleHighlight, 2.0); // More focused highlights
    baseColor.rgb += vec3(1.0, 0.8, 0.5) * bubbleHighlight * bubbleIntensity * 1.5;
    
    // Add overall fizz glow effect
    float fizzGlow = sin(u_Time * fizzGlowFrequency) * 0.5 + 0.5;
    fizzGlow = fizzGlow * 0.1; // Subtle effect
    
    // Apply glow - stronger at edges like a glass of soda
    float edgeGlow = smoothstep(0.0, 0.8, distFromCenter);
    baseColor.rgb += orangeColor * fizzGlow * edgeGlow;
    
    // Add sparkle effect - tiny random sparkles
    float sparklePhase = fract(v_TexCoord.x * 10.0 + v_TexCoord.y * 8.0 + u_Time * 0.5);
    float sparkle = step(0.995, sparklePhase); // Only top 0.5% of values become sparkles
    baseColor.rgb += vec3(1.0) * sparkle * 0.5; // White sparkles
    
    // Set output color
    gl_FragColor = baseColor;
} 