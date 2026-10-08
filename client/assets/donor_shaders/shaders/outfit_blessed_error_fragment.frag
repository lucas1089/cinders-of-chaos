uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Blessed parameters
float glowIntensity = 0.45; // Overall holy glow intensity
float rayIntensity = 0.5; // Intensity of golden rays
float pulseBrightness = 0.2; // Pulse brightness variation

// Pseudo-random function from gold shader
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
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
    
    // Check if this texture has color masks
    bool hasMasks = (texcolor.r > 0.9 || texcolor.g > 0.9 || texcolor.b > 0.9);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Get distance from center and time from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float currentTime = v_TexCoord3.y;
    
    // Calculate angle for ray effect
    vec2 centeredCoord = v_TexCoord - vec2(0.5, 0.5);
    float angle = atan(centeredCoord.y, centeredCoord.x);
    
    // Create holy gold colors
    vec3 holyGold = vec3(1.0, 0.9, 0.4); // Bright gold
    vec3 holyWhite = vec3(1.0, 1.0, 0.95); // Almost white
    
    // Create pulsing glow that gets stronger at the edges
    float pulse = sin(currentTime * 0.8) * 0.5 + 0.5;
    float edgeGlow = smoothstep(0.0, 0.8, distFromCenter);
    float glowFactor = mix(0.2, 1.0, edgeGlow) * pulse * glowIntensity;
    
    // Apply glow
    baseColor.rgb = mix(baseColor.rgb, holyGold, glowFactor);
    
    // Create ray effect with smoother transition
    float rayAngle = sin(angle * 8.0 + currentTime * 1.2);
    // Use smoothstep instead of pow for smoother rays
    float rayMask = smoothstep(0.3, 0.7, rayAngle * 0.5 + 0.5);
    
    // Make rays stronger at the center and pulse with smoother falloff
    float rayFactor = rayMask * smoothstep(1.0, 0.0, distFromCenter) * rayIntensity * (pulse + 0.5);
    
    // Apply rays with improved blending
    baseColor.rgb = mix(baseColor.rgb, holyWhite, rayFactor);
    
    // Add overall brightness pulsing
    float brightnessPulse = sin(currentTime * 0.6) * 0.5 + 0.5;
    baseColor.rgb += brightnessPulse * pulseBrightness * holyGold;
    
    // Create segmented armor plate effect from metallic gold shader
    // This helps with textures that don't have color masks
    float armorSegmentSize = 0.15; // Size of segments
    vec2 normalizedPos = centeredCoord * 2.0; // Scale to -1 to 1 range
    vec2 armorSegment = floor(normalizedPos / armorSegmentSize);
    float segmentVariation = sin(armorSegment.x * 3.1 + armorSegment.y * 2.7 + currentTime * 0.5) * 0.5 + 0.5;
    
    // Add gold-style sparkles with adaptive scaling for different outfit sizes
    vec2 uv = v_TexCoord;
    
    // Estimate relative size of the outfit from alpha channel spread
    // Sample a few points to determine approximate texture size
    float alphaSum = 0.0;
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            vec2 samplePoint = v_TexCoord + vec2(float(x), float(y)) * 0.03;
            alphaSum += texture2D(u_Tex0, samplePoint).a;
        }
    }
    
    // Adaptive sparkle size based on alpha spread (smaller for larger outfits)
    float adaptiveSize = mix(0.01, 0.005, min(1.0, alphaSum / 15.0));
    float sparkleSize = adaptiveSize; 
    float sparkleIntensity = 1.2; // Higher intensity for better visibility
    
    // Use different strategies for textures with and without masks
    if (hasMasks) {
        // Default sparkle approach for normal textured outfits
        // Add sparkle points with adaptive density
        int sparkleCount = 5; // More sparkles for better distribution
        for (int i = 0; i < sparkleCount; i++) {
            float timeOffset = float(i) * 0.7;
            
            // Scale adjustment for different sized outfits
            float baseScale = 12.0 + float(i) * 20.0;
            float scaleAdjust = mix(1.0, 0.6, min(1.0, alphaSum / 15.0)); // Reduce scale for larger outfits
            float scale = baseScale * scaleAdjust;
            
            // Create appropriately spaced grid for sparkles
            vec2 gridPos = floor(uv * scale) / scale;
            float r = random(gridPos);
            
            // Make sparkles appear and disappear with timing variation
            float sparkle = r * sin(currentTime * (2.5 + r * 2.5) + timeOffset) * 0.5 + 0.5;
            sparkle = pow(sparkle, 3.5) * sparkleIntensity;
            
            // Adaptive threshold for sparkle visibility based on outfit size
            float threshold = mix(0.3, 0.25, min(1.0, alphaSum / 15.0));
            if (sparkle > threshold) {
                // Distance from current fragment to center of sparkle grid cell
                vec2 center = gridPos + vec2(0.5) / scale;
                float dist = distance(uv, center);
                
                // Add sparkle if we're inside the sparkle radius
                if (dist < sparkleSize) {
                    // Smoother fade toward edges for larger outfits
                    float fade = 1.0 - dist / sparkleSize;
                    fade = pow(fade, 1.3); // Softer edges
                    
                    // Add bright sparkle to fragment color with size-aware intensity
                    float sizeAwareIntensity = mix(1.9, 1.5, min(1.0, alphaSum / 15.0));
                    baseColor.rgb += holyWhite * sparkle * fade * sizeAwareIntensity;
                }
            }
        }
    } else {
        // For outfits without color masks, use segmented approach similar to metallic gold
        // Create scan line effect
        float scanLine = sin(normalizedPos.y * 20.0 + currentTime * 0.5) * 0.5 + 0.5;
        scanLine = pow(scanLine, 2.0) * 0.15 * segmentVariation;
        
        // Apply scan lines
        baseColor.rgb += holyGold * scanLine;
        
        // Add segment-based sparkles for more controlled distribution
        for (int i = 0; i < 3; i++) {
            // Make each armor segment have its own sparkle timing
            float segmentSparkle = pow(sin(currentTime * (1.5 + segmentVariation * 2.0) + 
                                        armorSegment.x * 7.3 + 
                                        armorSegment.y * 5.2 + 
                                        float(i) * 1.1) * 0.5 + 0.5, 6.0);
            
            // Only show strong sparkles
            if (segmentSparkle > 0.7) {
                baseColor.rgb += holyWhite * segmentSparkle * 0.4 * segmentVariation;
            }
        }
    }
    
    // Add expanding ring effect with smoother transitions
    float ringPhase = fract(currentTime * 0.4); // Slow expansion
    float ringRadius = ringPhase * 0.8; // Maximum radius of 0.8
    float ringWidth = 0.05; // Wider ring for smoother transition
    
    // How close current pixel is to the ring - use smoothstep for better transition
    float ringDistance = abs(distFromCenter - ringRadius);
    float ringFactor = smoothstep(ringWidth, 0.0, ringDistance);
    
    // Apply ring with gradient that continues beyond the ring
    baseColor.rgb += holyGold * ringFactor * 0.3;
    
    // Apply a subtle continuous gradient that doesn't stop at pixelated lines
    float continuousGradient = smoothstep(0.0, 1.0, distFromCenter) * 0.15;
    baseColor.rgb = mix(baseColor.rgb, holyGold, continuousGradient * pulse);
    
    // Set output color
    gl_FragColor = baseColor;
} 