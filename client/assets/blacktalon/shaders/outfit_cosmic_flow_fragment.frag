uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Cosmic flow parameters
float starDensity = 0.05;       // Density of stars
float starBrightness = 0.7;     // Brightness of stars
float pixelSpeed = 1.0;         // Speed of flowing pixels
float pixelSize = 0.015;        // Size of flowing pixels
float pixelDensity = 0.5;       // Density of flowing pixels
float tailLength = 0.25;        // Length of pixel trails
float flickerSpeed = 2.0;       // Speed of star flickering

// Hash function for randomization
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
    
    // Create black space background
    vec3 spaceColor = vec3(0.0, 0.0, 0.03); // Very dark blue for space
    
    // Generate stars (static white/yellow dots)
    vec2 starUV = v_TexCoord * 10.0; // Scale for more stars
    
    // Initialize star color accumulator
    vec3 starColor = vec3(0.0);
    
    // Multiple layers of stars with different sizes and densities
    for (int i = 0; i < 3; i++) {
        float layerScale = 1.0 + float(i) * 2.0;
        float starSize = 0.95 + 0.03 * float(i); // Threshold for star brightness
        
        vec2 id = floor(starUV * layerScale);
        vec2 fd = fract(starUV * layerScale);
        
        // Generate random values based on position
        float r1 = hash(id);
        float r2 = hash(id + vec2(1.0, 0.0));
        
        // Only create stars where the random value is above threshold
        if (r1 > (1.0 - starDensity * (1.0 - float(i) * 0.2))) {
            // Random star color (white to yellowish)
            float yellowness = hash(id + vec2(0.0, 3.0)) * 0.5; // How yellow the star is
            vec3 thisStarColor = mix(vec3(1.0), vec3(1.0, 0.9, 0.6), yellowness);
            
            // Random star position within grid cell
            vec2 randomOffset = vec2(
                hash(id + vec2(5.2, 1.3)) * 0.8 + 0.1,
                hash(id + vec2(8.3, 2.5)) * 0.8 + 0.1
            );
            
            // Distance to star center
            float dist = length(fd - randomOffset);
            
            // Star shape with soft glow
            float brightness = smoothstep(0.05 * (1.0 + float(i) * 0.5), 0.0, dist);
            
            // Flicker effect
            float flicker = sin(u_Time * flickerSpeed * r2 + r1 * 6.28) * 0.5 + 0.5;
            flicker = 0.8 + flicker * 0.2; // 80% to 100% brightness
            
            // Add star to accumulator
            starColor += thisStarColor * brightness * flicker * starBrightness * (1.0 - float(i) * 0.2);
        }
    }
    
    // Generate flowing pixels from left to right
    vec3 pixelFlowColor = vec3(0.0);
    float time = u_Time * pixelSpeed;
    
    // Multiple layers of flowing pixels
    for (int i = 0; i < 5; i++) {
        float layerSpeed = 1.0 + float(i) * 0.4; // Different speeds per layer
        float layerOffset = float(i) * 1.3; // Offset layers
        
        // Create grid for pixels
        vec2 pixelUV = v_TexCoord * 5.0;
        pixelUV.x -= time * layerSpeed; // Move from left to right
        pixelUV.y += layerOffset; // Offset layers
        
        vec2 pixelID = floor(pixelUV);
        vec2 pixelFD = fract(pixelUV);
        
        // Only create pixels where random value is above threshold
        float r = hash(pixelID);
        if (r > (1.0 - pixelDensity * (1.0 - float(i) * 0.15))) {
            // Random pixel color (white to blue-ish)
            float blueHue = hash(pixelID + vec2(3.3, 7.1));
            vec3 thisPixelColor = mix(vec3(1.0), vec3(0.7, 0.8, 1.0), blueHue);
            
            // Random pixel position within grid cell
            vec2 randomOffset = vec2(
                hash(pixelID + vec2(9.2, 4.1)) * 0.6 + 0.2,
                hash(pixelID + vec2(2.9, 8.3)) * 0.6 + 0.2
            );
            
            // Distance to pixel center
            float dist = length(pixelFD - randomOffset);
            
            // Pixel shape with soft edges
            float pixelBrightness = smoothstep(pixelSize * (1.0 + float(i) * 0.3), 0.0, dist);
            
            // Create trailing effect (tail behind pixel)
            float tailX = pixelFD.x - randomOffset.x + tailLength;
            float tailY = abs(pixelFD.y - randomOffset.y);
            float tail = 0.0;
            
            if (tailX > 0.0 && tailX < tailLength && tailY < pixelSize * 2.0) {
                // Tail fades out with distance
                tail = (1.0 - tailX / tailLength) * smoothstep(pixelSize * 2.0, 0.0, tailY);
            }
            
            // Add pixel and tail to color
            pixelFlowColor += thisPixelColor * (pixelBrightness + tail * 0.5) * (1.0 - float(i) * 0.15);
        }
    }
    
    // Combine space background, stars and flowing pixels
    vec3 finalColor = spaceColor + starColor + pixelFlowColor;
    
    // Apply cosmic colors to the outfit while preserving some of the original texture details
    baseColor.rgb = mix(baseColor.rgb, finalColor, 0.85);
    
    // Set output color
    gl_FragColor = baseColor;
} 