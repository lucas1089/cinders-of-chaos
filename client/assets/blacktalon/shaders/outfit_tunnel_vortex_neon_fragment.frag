uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Parameters to adjust effect
float speedMultiplier = 1.4;     // Speed of scrolling - faster for neon effect
float colorIntensity = 25.0;     // Lower intensity for more saturated colors
float stepSize = 0.012;          // Base raymarch step size
float rippleIntensity = 0.18;    // Increased ripple intensity for neon effect

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
        
        // Add coloring - NEON variation (create cycling neon colors)
        vec3 color = (sin(p * 0.33) + 1.0105) / d / z;
        
        // Create rainbow neon effect by modulating the colors
        float phase = u_Time * 0.2 + i * 0.02;
        float sinPhase = sin(phase);
        float cosPhase = cos(phase);
        float sinPhase2 = sin(phase * 1.3);
        
        // Create vibrant neon colors that cycle over time
        color.r = color.r * (1.2 + 0.8 * sinPhase);
        color.g = color.g * (1.2 + 0.8 * cosPhase);
        color.b = color.b * (1.2 + 0.8 * sinPhase2);
        
        O.rgb += color;
    }
    
    // Tanh tonemapping (manual implementation for GLSL ES compatibility)
    vec4 tanhInput = O / colorIntensity;
    vec4 e2x = exp(2.0 * tanhInput);
    O = (e2x - 1.0) / (e2x + 1.0);
    
    // Enhance saturation for neon look
    vec3 gray = vec3(dot(O.rgb, vec3(0.299, 0.587, 0.114)));
    O.rgb = mix(gray, O.rgb, 1.6); // Oversaturate for neon effect
    
    // Add glow effect
    float glow = sin(u_Time * 2.0) * 0.5 + 0.5;
    O.rgb *= 1.0 + glow * 0.3;
    
    // Add neon pulse along edges
    float distFromCenter = length(I);
    float edgePulse = smoothstep(0.8, 1.0, distFromCenter) * sin(u_Time * 3.0 + distFromCenter * 5.0) * 0.5 + 0.5;
    O.rgb += edgePulse * vec3(0.2, 0.5, 0.8) * 0.3;
    
    // Mix with original texture
    float effectStrength = 0.9; // Higher strength for more dominant neon effect
    baseColor.rgb = mix(baseColor.rgb, O.rgb, effectStrength);
    
    // Set output color
    gl_FragColor = baseColor;
} 