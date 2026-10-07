uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Parameters to adjust effect
float speedMultiplier = 1.25;    // Speed of scrolling
float colorIntensity = 28.0;     // Intensity of colors
float stepSize = 0.013;          // Base raymarch step size
float rippleIntensity = 0.16;    // Intensity of ripple effect

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
        
        // Add coloring - PURPLE variation (boost red and blue channels)
        vec3 color = (sin(p * 0.33) + 1.0105) / d / z;
        color.r *= 1.4;   // Boost red
        color.g *= 0.2;   // Reduce green significantly
        color.b *= 1.6;   // Boost blue more
        
        O.rgb += color;
    }
    
    // Tanh tonemapping (manual implementation for GLSL ES compatibility)
    vec4 tanhInput = O / colorIntensity;
    vec4 e2x = exp(2.0 * tanhInput);
    O = (e2x - 1.0) / (e2x + 1.0);
    
    // Add purple glow
    O.r = min(1.0, O.r * 1.1);
    O.b = min(1.0, O.b * 1.3);
    
    // Create pulsing effect
    float pulse = sin(u_Time * 0.5) * 0.5 + 0.5;
    O.r += pulse * 0.1;
    O.b += pulse * 0.15;
    
    // Add mystical pattern
    float mysticalPattern = sin(8.0 * length(I) - u_Time * 2.5) * 0.05;
    O.b += mysticalPattern;
    O.r += mysticalPattern * 0.8;
    
    // Mix with original texture
    float effectStrength = 0.85;
    baseColor.rgb = mix(baseColor.rgb, O.rgb, effectStrength);
    
    // Set output color
    gl_FragColor = baseColor;
} 