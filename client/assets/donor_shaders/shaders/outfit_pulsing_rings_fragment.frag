uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Pulsing rings parameters
float ringWidth = 0.05;          // Width of each ring
float ringSpacing = 0.25;        // Spacing between rings
float ringSpeed = 0.5;           // Speed of upward movement
float ringGlow = 0.8;            // Intensity of ring glow
float ringColor1Intensity = 0.8; // Intensity of primary ring color
float ringColor2Intensity = 0.6; // Intensity of secondary ring color
float pulseFrequency = 2.0;      // Frequency of pulse effect
float pulseAmount = 0.3;         // Amount of pulse effect

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
    float distFromCenter = v_TexCoord3.x; // Distance from center (0-1)
    float angle = v_TexCoord3.y; // Angular position
    
    // Create normalized position for rings (centered at 0, 0)
    vec2 ringPos = vec2(v_TexCoord.x - 0.5, v_TexCoord.y - 0.5) * 2.0;
    float dist = length(ringPos); // Distance from center (0-1)
    
    // Time for ring movement
    float time = u_Time * ringSpeed;
    
    // Initialize ring color accumulator
    vec3 ringColor = vec3(0.0);
    float totalRingAlpha = 0.0;
    
    // Create multiple rings
    for (int i = 0; i < 4; i++) {
        // Offset each ring in time and space
        float ringOffset = float(i) * ringSpacing;
        float adjustedTime = time + ringOffset;
        
        // Calculate ring position (moves upward)
        // Map the time to a repeating 0-1 range
        float ringPos = fract(adjustedTime);
        
        // Calculate distance to this ring
        // Map the distance for vertical movement (distance grows as rings move up)
        float distToRing = abs(dist - ringPos);
        
        // Create pulse effect
        float pulse = sin(u_Time * pulseFrequency + float(i) * 1.5) * 0.5 + 0.5;
        pulse = 1.0 + pulse * pulseAmount; // Scale from 1.0 to 1.3
        
        // Apply pulse to ring width
        float adjustedRingWidth = ringWidth * pulse;
        
        // Calculate ring intensity with smooth falloff
        float ringIntensity = smoothstep(adjustedRingWidth, 0.0, distToRing);
        
        // Create color for this ring
        // Use two colors that cycle between rings
        vec3 ringColor1 = vec3(0.3, 0.7, 1.0); // Bright blue
        vec3 ringColor2 = vec3(1.0, 0.5, 0.0); // Orange
        
        // Alternate between colors for successive rings
        vec3 thisRingColor = mix(ringColor1, ringColor2, sin(float(i) * 1.57) * 0.5 + 0.5);
        
        // Apply color intensity
        thisRingColor *= mix(ringColor2Intensity, ringColor1Intensity, sin(float(i) * 1.57) * 0.5 + 0.5);
        
        // Add glow effect
        float glow = smoothstep(adjustedRingWidth * 2.0, 0.0, distToRing);
        glow *= glow; // Square for more focused glow
        glow *= ringGlow;
        
        // Make rings more visible at edges of the sprite
        float edgeFactor = smoothstep(0.3, 0.8, dist);
        
        // Add this ring's contribution
        ringColor += thisRingColor * ringIntensity + thisRingColor * glow * edgeFactor;
        totalRingAlpha += ringIntensity + glow * edgeFactor;
    }
    
    // Create an overall pulse effect that affects the entire outfit
    float globalPulse = sin(u_Time * 1.5) * 0.5 + 0.5;
    globalPulse = globalPulse * 0.2 + 0.8; // Scale from 0.8 to 1.0
    
    // Apply global pulse to ring brightness
    ringColor *= globalPulse;
    
    // Mix rings with base color based on ring opacity
    totalRingAlpha = min(totalRingAlpha, 0.9); // Cap the total alpha
    baseColor.rgb = mix(baseColor.rgb, ringColor, totalRingAlpha);
    
    // Add subtle ambient glow to entire outfit
    float ambientGlow = globalPulse * 0.15;
    vec3 glowColor = mix(vec3(0.3, 0.7, 1.0), vec3(1.0, 0.5, 0.0), sin(u_Time * 0.3) * 0.5 + 0.5);
    baseColor.rgb += glowColor * ambientGlow;
    
    // Set output color
    gl_FragColor = baseColor;
} 