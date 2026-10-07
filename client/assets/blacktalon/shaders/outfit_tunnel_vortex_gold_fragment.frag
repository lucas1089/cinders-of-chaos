uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Parameters to adjust effect
float speedMultiplier = 1.0;     // Slower speed for regal gold effect
float colorIntensity = 32.0;     // Intensity of colors
float stepSize = 0.015;          // Base raymarch step size
float rippleIntensity = 0.13;    // Intensity of ripple effect
float effectStrength = 0.85;     // Effect strength

void main() {
    // Sample texture without checking alpha first
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Store original alpha for final blending
    float originalAlpha = baseColor.a;
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Get normalized coordinates (0-1 range)
    vec2 uv = v_TexCoord;
    
    // Center coordinates for effect (-0.5 to 0.5 range)
    vec2 I = (uv - 0.5) * 2.0;
    
    // Scale to aspect ratio
    I.x *= u_Resolution.x / u_Resolution.y;
    
    // Time for scrolling
    float t = u_Time * speedMultiplier;
    
    // Initialize variables
    float i = 0.0;          // Raymarch iterator
    float d = 0.0;          // Raymarch step distance
    float z = 0.0;          // Raymarch depth
    vec4 O = vec4(0.0);     // Output color
    
    // Raymarch 30 steps
    for(; i < 30.0; i++) {
        // Compute ray direction 
        vec3 r = normalize(vec3(3.3 * I, 0.0) - vec3(u_Resolution.xy, 0.0));
        
        // Raymarch sample position
        vec3 p = z * r;
        
        // Raytraced ceiling coordinates
        vec3 w = r / abs(r.y);
        
        // Scroll forward
        w.z -= t;
        p.z -= t;
        
        // Shift camera
        r = ++p;
        
        // Reflect ceiling
        p.y = abs(mod(p.y - 1.0, 1.0) - 0.5);
        
        // Step forward
        d = stepSize + 
            // Distance to lights
            0.5 * length(sin(p + p).xz + p.y * 0.2) +
            // Ripply reflection bias
            rippleIntensity * exp(sin(length(sin(w)) * 777.0 + p.z)) * length(p - r);
        
        z += d;
        
        // Add coloring - GOLD variation (boost red and green channels, slight blue)
        vec3 color = (sin(p * 0.33) + 1.0105) / d / z;
        color.r *= 1.8;   // Strong red
        color.g *= 1.4;   // Medium-high green
        color.b *= 0.2;   // Very low blue
        
        O.rgb += color;
    }
    
    // Tanh tonemapping (manual implementation for GLSL ES compatibility)
    vec4 tanhInput = O / colorIntensity;
    vec4 e2x = exp(2.0 * tanhInput);
    O = (e2x - 1.0) / (e2x + 1.0);
    
    // Add golden glow
    O.r = min(1.0, O.r * 1.2);
    O.g = min(1.0, O.g * 1.1);
    
    // Create subtle pulsing effect (more subdued for gold)
    float pulse = sin(u_Time * 0.4) * 0.5 + 0.5;
    O.r += pulse * 0.08;
    O.g += pulse * 0.06;
    
    // Add metallic pattern for gold effect
    float goldPattern = sin(6.0 * length(I) + u_Time) * 0.04;
    float metallicHighlight = pow(sin(u_Time * 0.3 + length(I) * 6.0) * 0.5 + 0.5, 3.0) * 0.15;
    
    O.r += goldPattern + metallicHighlight;
    O.g += goldPattern * 0.7 + metallicHighlight * 0.7;
    O.b += metallicHighlight * 0.3; // Just a hint of blue in highlights
    
    // Get distance from center for effect intensity
    float distFromCenter = v_TexCoord3.x;
    float edgeFade = smoothstep(1.1, 0.8, distFromCenter); // Fade in from edges
    
    // Adjust effect intensity based on distance
    float finalStrength = effectStrength;
    if (originalAlpha < 0.01) {
        // For fully transparent areas, reduce effect but still visible
        finalStrength *= 0.6;
    } else {
        // For semi-transparent areas, maintain visibility
        finalStrength = mix(effectStrength * 0.7, effectStrength, originalAlpha);
    }
    
    // Mix with original texture
    baseColor.rgb = mix(baseColor.rgb, O.rgb, finalStrength * edgeFade);
    
    // Set output color - keep original alpha for proper blending
    // But ensure effect is visible with minimum alpha
    float finalAlpha = originalAlpha;
    if (originalAlpha < 0.01 && length(O.rgb) > 0.2) {
        // Add minimum alpha where effect is visible even on transparent pixels
        finalAlpha = 0.3 * edgeFade * length(O.rgb);
    }
    
    gl_FragColor = vec4(baseColor.rgb, finalAlpha);
} 