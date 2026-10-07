uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Swamp with bugs parameters
float swampIntensity = 0.7; // Intensity of swamp effect
float bugIntensity = 0.5; // Intensity of bugs
float bugSize = 0.004; // Size of bugs
float bugCount = 15.0; // Number of bugs

// Hash function for random values
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

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
    
    // Get bug time from vertex shader
    float bugTime = v_TexCoord3.x;
    float distFromCenter = v_TexCoord3.y;
    
    // Apply greenish swamp tint
    vec3 swampColor = vec3(0.2, 0.4, 0.1); // Dark green
    baseColor.rgb = mix(baseColor.rgb, swampColor, distFromCenter * swampIntensity * 0.3);
    
    // Add swamp bubble effect
    float bubblePattern = sin(v_TexCoord.x * 20.0 + v_TexCoord.y * 15.0 + bugTime * 0.3);
    float bubbles = smoothstep(0.7, 0.9, bubblePattern) * distFromCenter;
    baseColor.rgb = mix(baseColor.rgb, vec3(0.3, 0.5, 0.2), bubbles * 0.3); // Light green bubbles
    
    // Create bug swarm
    float bugs = 0.0;
    
    // Generate several bugs with different flight patterns
    for (float i = 0.0; i < bugCount; i++) {
        // Create semi-random position for each bug
        float bugSeed = i / bugCount;
        
        // Create random flight path for each bug
        float bugX = sin(bugTime * (0.5 + bugSeed) + bugSeed * 6.28) * 0.5;
        float bugY = cos(bugTime * (0.7 + bugSeed * 0.5) + bugSeed * 6.28) * 0.5;
        
        // Apply a spiral pattern overall
        float spiral = bugTime * (0.2 + bugSeed * 0.3);
        bugX += sin(spiral) * (0.3 + bugSeed * 0.2);
        bugY += cos(spiral) * (0.3 + bugSeed * 0.2);
        
        // Scale to fit around character
        bugX = bugX * 0.5 + 0.5; // 0 to 1 range
        bugY = bugY * 0.5 + 0.5; // 0 to 1 range
        
        // Calculate distance to bug
        float bugDist = distance(vec2(bugX, bugY), v_TexCoord);
        
        // Create bug circle with random size variation
        float bugVariation = hash(vec2(i, bugTime * 0.1));
        float thisBugSize = bugSize * (0.7 + bugVariation * 0.6);
        float bug = smoothstep(thisBugSize, 0.0, bugDist);
        
        // Make bug brighter or dimmer based on random variation
        bug *= 0.7 + bugVariation * 0.5;
        
        // Add this bug to total
        bugs += bug;
    }
    
    // Add bug swarm visual effect
    vec3 bugColor1 = vec3(0.8, 0.8, 0.1); // Yellowish bugs
    vec3 bugColor2 = vec3(0.7, 0.6, 0.1); // Darker yellow bugs
    
    // Mix bug colors based on time
    vec3 finalBugColor = mix(bugColor1, bugColor2, sin(bugTime * 0.5) * 0.5 + 0.5);
    
    // Apply bugs with proper intensity
    baseColor.rgb = mix(baseColor.rgb, finalBugColor, bugs * bugIntensity);
    
    // Create subtle glow around bugs
    float bugGlow = smoothstep(bugSize * 4.0, bugSize, bugs);
    baseColor.rgb += finalBugColor * bugGlow * 0.2 * bugIntensity;
    
    // Set output color
    gl_FragColor = baseColor;
} 