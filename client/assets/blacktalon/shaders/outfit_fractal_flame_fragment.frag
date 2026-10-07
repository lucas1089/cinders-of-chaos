uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Fractal parameters
float colorScale = 3.0;      // Scale of color transitions
float speed = 0.5;           // Animation speed
float brightness = 1.3;      // Overall brightness
float smoothing = 2.0;       // Smoothing factor for color transitions

// Generate smooth fractal pattern with clear color regions
vec3 smoothFractal(vec2 coord, float time) {
    // Scale coordinates for larger patterns
    vec2 pos = coord * 3.0;
    
    // Create smooth flowing noise pattern
    float timeFlow = time * 0.3;
    
    // Base pattern with multiple frequency components
    float pattern1 = sin(pos.x * 1.5 + timeFlow) * cos(pos.y * 1.5 - timeFlow * 0.7);
    float pattern2 = sin(pos.x * 2.3 - pos.y * 1.8 + timeFlow * 1.1);
    float pattern3 = cos(length(pos) * 3.0 - timeFlow * 0.5);
    float pattern4 = sin(pos.x * 0.8 + pos.y * 0.8 + timeFlow * 0.3) * 0.7;
    
    // Combine patterns
    float mainPattern = (pattern1 + pattern2 + pattern3 + pattern4) * 0.25;
    mainPattern = mainPattern * 0.5 + 0.5; // Normalize to 0-1 range
    
    // Create smooth transitions between color regions
    float colorRegion = smoothstep(0.0, 1.0, mainPattern);
    
    // Create swirling time-based color adjustment for vibrance
    float swirl = sin(atan(coord.y, coord.x) * 3.0 + time) * 0.5 + 0.5;
    
    // Create clear color regions using the pattern
    vec3 color;
    
    // Use the color value to select between 4 primary colors
    if (colorRegion < 0.25) {
        // Red region
        color = mix(
            vec3(1.0, 0.1, 0.05), // Deep red
            vec3(1.0, 0.3, 0.1),  // Bright red-orange
            smoothstep(0.0, 0.25, colorRegion) * swirl
        );
    } else if (colorRegion < 0.5) {
        // Yellow region
        color = mix(
            vec3(1.0, 0.7, 0.1),  // Orange-yellow
            vec3(1.0, 1.0, 0.2),  // Bright yellow
            smoothstep(0.25, 0.5, colorRegion) * swirl
        );
    } else if (colorRegion < 0.75) {
        // Green region
        color = mix(
            vec3(0.2, 0.9, 0.2),  // Bright green
            vec3(0.1, 0.7, 0.4),  // Emerald green
            smoothstep(0.5, 0.75, colorRegion) * swirl
        );
    } else {
        // Blue region
        color = mix(
            vec3(0.1, 0.5, 0.9),  // Royal blue
            vec3(0.2, 0.2, 1.0),  // Electric blue
            smoothstep(0.75, 1.0, colorRegion) * swirl
        );
    }
    
    // Add glowing effect based on the pattern
    float glow = pow(mainPattern, 2.0) * 0.5 + 0.5;
    color *= glow * brightness;
    
    // Add some white hot spots at intensity peaks
    float hotspot = pow(mainPattern, 8.0) * 2.0;
    color = mix(color, vec3(1.0), hotspot);
    
    return color;
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
    
    // Extract distance and angle from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float angle = v_TexCoord3.y;
    
    // Create coordinates for fractal
    vec2 fractalCoord = vec2(
        cos(angle) * distFromCenter,
        sin(angle) * distFromCenter
    );
    
    // Get animated fractal pattern
    float time = u_Time * speed;
    vec3 fractal = smoothFractal(fractalCoord, time);
    
    // Create smooth flowing edge effect
    float edgeGlow = smoothstep(0.0, 0.6, distFromCenter) * smoothstep(1.1, 0.7, distFromCenter);
    
    // Enhance colors at edges with flowing patterns
    vec3 edgeColor = vec3(1.0);
    float edgeTime = time * 0.7;
    
    // Create changing edge colors
    if (mod(edgeTime, 4.0) < 1.0) {
        edgeColor = vec3(1.0, 0.3, 0.1); // Red
    } else if (mod(edgeTime, 4.0) < 2.0) {
        edgeColor = vec3(1.0, 0.9, 0.1); // Yellow
    } else if (mod(edgeTime, 4.0) < 3.0) {
        edgeColor = vec3(0.1, 1.0, 0.3); // Green
    } else {
        edgeColor = vec3(0.1, 0.4, 1.0); // Blue
    }
    
    fractal += edgeColor * edgeGlow * 0.5;
    
    // Apply a subtle influence from the outfit colors
    vec3 outfitHue = baseColor.rgb / max(max(baseColor.r, baseColor.g), max(baseColor.b, 0.001));
    fractal = mix(fractal, fractal * outfitHue, 0.2); // Just a touch of outfit color influence
    
    // Mix with original texture - stronger effect in the center
    float effectStrength = (1.0 - distFromCenter * 0.5) * 0.85;
    baseColor.rgb = mix(baseColor.rgb, fractal, effectStrength);
    
    // Add extra bright center glow
    float centerGlow = smoothstep(0.4, 0.0, distFromCenter);
    baseColor.rgb += centerGlow * vec3(0.7, 0.7, 0.7) * (sin(time * 2.0) * 0.3 + 0.7);
    
    // Set output color
    gl_FragColor = baseColor;
} 