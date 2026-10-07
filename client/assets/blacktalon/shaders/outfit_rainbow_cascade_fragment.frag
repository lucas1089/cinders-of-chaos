uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Rainbow Cascade parameters
float ballSize = 0.04; // Size of the rainbow balls
float flowSpeed = 1.2; // Speed of downward flow
float flowAngle = 75.0; // Angle in degrees (90 = straight down, < 90 = right bias)
float ballGlow = 0.35; // Intensity of ball glow
float ballIntensity = 0.75; // Intensity of ball colors
float colorCycleSpeed = 0.2; // Speed of color cycling

// Simple hash function for randomization
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Simple noise function
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smooth interpolation
    
    float n = mix(
        mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
    
    return n;
}

// Distance function for creating circular balls
float circle(vec2 uv, vec2 center, float radius) {
    return smoothstep(radius, radius * 0.8, length(uv - center));
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
    
    // Extract data from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float time = u_Time * flowSpeed;
    
    // Calculate flow direction based on angle
    float angleRad = radians(flowAngle);
    vec2 flowDir = vec2(cos(angleRad), sin(angleRad));
    
    // Create grid of rainbow balls that move down and slightly right
    vec2 scaledUV = v_TexCoord * 4.0; // Scale for more balls
    
    // Apply moving offset in flow direction
    scaledUV += flowDir * time;
    
    // Initialize the color accumulator for all balls
    vec3 ballsColor = vec3(0.0);
    float totalWeight = 0.0;
    
    // Create several layers of balls with different sizes and speeds
    for (int layerIdx = 0; layerIdx < 3; layerIdx++) {
        float layerScale = 1.0 + float(layerIdx) * 0.7; // Different scales
        float layerSpeed = 1.0 + float(layerIdx) * 0.3; // Different speeds
        float layerOffset = float(layerIdx) * 2.5; // Offset the patterns
        
        // Create grid points (ball centers)
        vec2 id = floor(scaledUV * layerScale);
        vec2 gv = fract(scaledUV * layerScale) - 0.5;
        
        // For each ball, create a random hue based on position and time
        float hue = hash(id) + time * colorCycleSpeed * layerSpeed;
        
        // Random offset to make the pattern less grid-like
        vec2 rnd = vec2(
            hash(id + vec2(27.3, 15.4)) * 2.0 - 1.0,
            hash(id + vec2(7.1, 38.2)) * 2.0 - 1.0
        ) * 0.25;
        
        // Calculate distance to the center of the circle
        float dist = length(gv - rnd);
        
        // Create circle with soft edges
        float circle = smoothstep(ballSize * layerScale, ballSize * 0.8 * layerScale, dist);
        
        // Create rainbow color for this ball
        vec3 ballColor;
        float h = fract(hue) * 6.0;
        float hueIndex = floor(h);
        float f = h - hueIndex;
        float q = 1.0 - f;
        
        if (hueIndex == 0.0) ballColor = vec3(1.0, f, 0.0);
        else if (hueIndex == 1.0) ballColor = vec3(q, 1.0, 0.0);
        else if (hueIndex == 2.0) ballColor = vec3(0.0, 1.0, f);
        else if (hueIndex == 3.0) ballColor = vec3(0.0, q, 1.0);
        else if (hueIndex == 4.0) ballColor = vec3(f, 0.0, 1.0);
        else ballColor = vec3(1.0, 0.0, q);
        
        // Make colors more vibrant
        ballColor = pow(ballColor, vec3(0.8)); // Boost saturation
        
        // Accumulate this ball's color
        ballsColor += ballColor * circle;
        totalWeight += circle;
    }
    
    // Normalize the accumulated color
    if (totalWeight > 0.0) {
        ballsColor /= totalWeight;
    }
    
    // Create final ball effect with glow
    vec3 finalBallEffect = ballsColor * ballIntensity;
    
    // Add glow based on ball brightness
    vec3 glowColor = ballsColor * 1.5; // Brighter version for glow
    finalBallEffect += glowColor * ballGlow * (1.0 - distFromCenter);
    
    // Mix with base color based on ball opacity
    baseColor.rgb = mix(baseColor.rgb, finalBallEffect, min(1.0, totalWeight * 0.7));
    
    // Set output color
    gl_FragColor = baseColor;
} 