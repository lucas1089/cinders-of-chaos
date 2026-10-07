uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Parameters to adjust effect
float speedMultiplier = 1.1;     // Speed of scrolling
float colorIntensity = 32.0;     // Intensity of colors
float stepSize = 0.014;          // Base raymarch step size
float rippleIntensity = 0.15;    // Intensity of ripple effect

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
        
        // Add coloring - BLUE variation (boost blue channel, reduce others)
        vec3 color = (sin(p * 0.33) + 1.0105) / d / z;
        color.r *= 0.3;  // Reduce red
        color.g *= 0.6;  // Reduce green slightly
        color.b *= 2.0;  // Boost blue significantly
        
        O.rgb += color;
    }
    
    // Tanh tonemapping (manual implementation for GLSL ES compatibility)
    vec4 tanhInput = O / colorIntensity;
    vec4 e2x = exp(2.0 * tanhInput);
    O = (e2x - 1.0) / (e2x + 1.0);
    
    // Add bluish glow
    O.b = min(1.0, O.b * 1.3);
    O.g = min(1.0, O.g * 1.1); // Add a slight cyan tint
    
    // Create pulsing effect
    float pulse = sin(u_Time * 0.8) * 0.5 + 0.5;
    O.b += pulse * 0.15;
    O.g += pulse * 0.05; // Subtle cyan pulse
    
    // Add water ripple effect
    float ripple = sin(10.0 * length(I) - u_Time * 3.0) * 0.05;
    O.rgb += vec3(0.0, 0.0, ripple);
    
    // Mix with original texture
    float effectStrength = 0.85;
    baseColor.rgb = mix(baseColor.rgb, O.rgb, effectStrength);
    
    // Set output color
    gl_FragColor = baseColor;
} 