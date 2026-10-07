uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Textured Pulsing Rings parameters
float ringWidth = 0.06;          // Width of each ring
float ringSpacing = 0.25;        // Spacing between rings
float ringSpeed = 0.6;           // Speed of upward movement
float ringGlow = 0.9;            // Intensity of ring glow
float textureIntensity = 0.9;    // Intensity of texture effect
float pulseFrequency = 1.8;      // Frequency of pulse effect
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
    
    // Extract data from vertex shader
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
    
    // Sample the texture for use in the rings (u_Tex1 is the extra texture we'll use)
    // We'll use multiple sampling points to create more interesting patterns
    vec2 texCoordShifted1 = v_TexCoord + vec2(sin(u_Time * 0.3) * 0.1, cos(u_Time * 0.4) * 0.1);
    vec2 texCoordShifted2 = v_TexCoord + vec2(cos(u_Time * 0.5) * 0.2, sin(u_Time * 0.6) * 0.2);
    vec2 texCoordShifted3 = v_TexCoord + vec2(sin(u_Time * 0.7) * 0.15, -cos(u_Time * 0.8) * 0.15);
    
    vec4 textureSample1 = texture2D(u_Tex1, texCoordShifted1);
    vec4 textureSample2 = texture2D(u_Tex1, texCoordShifted2);
    vec4 textureSample3 = texture2D(u_Tex1, texCoordShifted3);
    
    // Create multiple rings
    for (int i = 0; i < 5; i++) {
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
        
        // Apply texture colors for this ring
        // Different sampling for each ring for variation
        // Use mod() instead of % for GLSL ES compatibility
        vec3 textureColor;
        float ringMod = mod(float(i), 3.0);
        if (ringMod < 0.5) {
            textureColor = textureSample1.rgb;
        } else if (ringMod < 1.5) {
            textureColor = textureSample2.rgb;
        } else {
            textureColor = textureSample3.rgb;
        }
        
        // Enhance color brightness and saturation
        textureColor = pow(textureColor, vec3(0.8)); // Increase brightness
        textureColor = mix(vec3(length(textureColor)), textureColor, 1.3); // Increase saturation
        
        // Add rotation to the color based on angle and time
        float colorRotation = angle + u_Time * 0.2 + float(i) * 0.5;
        vec3 rotatedColor = vec3(
            textureColor.r * (0.7 + 0.3 * sin(colorRotation)),
            textureColor.g * (0.7 + 0.3 * sin(colorRotation + 2.09)),
            textureColor.b * (0.7 + 0.3 * sin(colorRotation + 4.18))
        );
        
        // Apply texture intensity
        rotatedColor *= textureIntensity;
        
        // Add glow effect
        float glow = smoothstep(adjustedRingWidth * 3.0, 0.0, distToRing);
        glow *= glow; // Square for more focused glow
        glow *= ringGlow;
        
        // Make rings more visible at edges of the sprite
        float edgeFactor = smoothstep(0.2, 0.8, dist);
        
        // Add this ring's contribution
        // Use the texture color modulated by the ring intensity
        ringColor += rotatedColor * ringIntensity + rotatedColor * 0.7 * glow * edgeFactor;
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
    vec3 avgTextureColor = (textureSample1.rgb + textureSample2.rgb + textureSample3.rgb) / 3.0;
    baseColor.rgb += avgTextureColor * ambientGlow;
    
    // Set output color
    gl_FragColor = baseColor;
} 