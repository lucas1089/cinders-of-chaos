uniform mat4 u_Color;
uniform sampler2D u_Tex0;
uniform float u_Time;

varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec4 v_Color;

// RGB to HSV conversion function
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB conversion function
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Function to get a Pantone-inspired color for gradient effect
vec3 getPantoneGradient(float pos) {
    // Pantone-inspired color pairs for gradients (GLSL ES compatible - no 2D arrays)
    // Start colors
    vec3 startColors[6];
    startColors[0] = vec3(0.929, 0.792, 0.686); // Peach Fuzz
    startColors[1] = vec3(0.541, 0.647, 0.710); // Blue Atoll
    startColors[2] = vec3(0.996, 0.922, 0.631); // Lemon Icing
    startColors[3] = vec3(0.863, 0.318, 0.506); // Beetroot Purple
    startColors[4] = vec3(0.365, 0.725, 0.667); // Spearmint
    startColors[5] = vec3(0.898, 0.439, 0.310); // Persimmon

    // End colors
    vec3 endColors[6];
    endColors[0] = vec3(0.894, 0.459, 0.565); // Mauveglow
    endColors[1] = vec3(0.286, 0.427, 0.541); // True Blue
    endColors[2] = vec3(0.839, 0.675, 0.231); // Honey Yellow
    endColors[3] = vec3(0.596, 0.651, 0.741); // Skyway
    endColors[4] = vec3(0.345, 0.643, 0.290); // Classic Green
    endColors[5] = vec3(0.945, 0.702, 0.251); // Vibrant Yellow

    // Select which gradient to use based on time and position
    float gradientSelector = fract((u_Time * 0.015) + (v_TexCoord.x * 0.1));
    int gradientIdx = int(mod(floor(gradientSelector * 6.0), 6.0));

    // Get the gradient start and end colors
    vec3 startColor = startColors[gradientIdx];
    vec3 endColor = endColors[gradientIdx];

    // Create a smoothed gradient
    return mix(startColor, endColor, smoothstep(0.0, 1.0, pos));
}

// Noise function for creating movement pattern
float noise(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main()
{
    // Sample the original texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Apply outfit colors based on the texture channels
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Set initial output color
    gl_FragColor = baseColor;
    
    if(texcolor.a > 0.9) {
        // Convert to HSV for easier manipulation
        vec3 hsv = rgb2hsv(baseColor.rgb);
        
        // Create flowing wave pattern
        float flowDirection = sin(-u_Time * 0.1) * 0.5 + 0.5; // Inverted and halved speed
        
        // Create diagonal wave pattern
        float diagonalPos = (v_TexCoord.x + v_TexCoord.y) * 0.5;
        float waveOffset = sin(-u_Time * 0.25) * 0.1; // Inverted and halved speed
        
        // Calculate gradient position with animated flow, removed noise/pixelization
        float gradientPos;
        
        if (flowDirection > 0.5) {
            // Flow from bottom-left to top-right
            gradientPos = fract(diagonalPos + waveOffset);
        } else {
            // Flow from top to bottom
            gradientPos = fract(v_TexCoord.y + waveOffset);
        }
        
        // Get pantone gradient color
        vec3 pantoneColor = getPantoneGradient(gradientPos);
        
        // Apply different color transformations based on brightness
        if (hsv.z > 0.7) {
            // For bright areas - use pantone colors at higher intensity
            vec3 brightPantone = pantoneColor * 1.3;
            gl_FragColor = vec4(brightPantone, baseColor.a);
        } else if (hsv.z > 0.3) {
            // For mid-tone areas - blend with original color
            vec3 blendedColor = mix(baseColor.rgb, pantoneColor, 0.8);
            gl_FragColor = vec4(blendedColor, baseColor.a);
        } else {
            // For darker areas - preserve more of the original color
            vec3 darkPantone = pantoneColor * hsv.z * 1.5; // Boost dark areas a bit
            vec3 blendedDark = mix(baseColor.rgb, darkPantone, 0.6);
            gl_FragColor = vec4(blendedDark, baseColor.a);
        }
        
        // Add subtle ripple highlights following the gradient
        float ripplePattern = sin((diagonalPos * 20.0) - u_Time * 1.0) * 0.5 + 0.5; // Inverted and halved speed
        float rippleHighlight = smoothstep(0.4, 0.6, ripplePattern) * 0.15;
        
        gl_FragColor.rgb += pantoneColor * rippleHighlight;
        
        // Add subtle inner glow
        float edgeGlow = (1.0 - distance(v_TexCoord, vec2(0.5))) * 0.2;
        gl_FragColor.rgb += pantoneColor * edgeGlow;
        
        // Ensure we don't exceed the maximum brightness
        gl_FragColor.rgb = min(gl_FragColor.rgb, vec3(1.0));
    }
    
    // Discard transparent pixels
    if(gl_FragColor.a < 0.01) discard;
} 