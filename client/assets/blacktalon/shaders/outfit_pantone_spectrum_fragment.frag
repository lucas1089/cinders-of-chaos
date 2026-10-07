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

// Random function for deterministic color selection
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Function to get a Pantone-inspired color based on input value
vec3 getPantoneColor(float value) {
    // Pantone-inspired colors (2023-2024 palette)
    vec3 colors[12];
    colors[0] = vec3(0.929, 0.792, 0.686);  // Pantone 13-1023 Peach Fuzz
    colors[1] = vec3(0.541, 0.647, 0.710);  // Pantone 18-4051 Blue Atoll
    colors[2] = vec3(0.996, 0.922, 0.631);  // Pantone 12-0825 Lemon Icing
    colors[3] = vec3(0.863, 0.318, 0.506);  // Pantone 18-2143 Beetroot Purple
    colors[4] = vec3(0.365, 0.725, 0.667);  // Pantone 15-5519 Spearmint
    colors[5] = vec3(0.839, 0.675, 0.231);  // Pantone 16-0946 Honey Yellow
    colors[6] = vec3(0.898, 0.439, 0.310);  // Pantone 16-1546 Persimmon
    colors[7] = vec3(0.286, 0.427, 0.541);  // Pantone 19-4127 True Blue
    colors[8] = vec3(0.345, 0.643, 0.290);  // Pantone 15-6340 Classic Green
    colors[9] = vec3(0.894, 0.459, 0.565);  // Pantone 16-2126 Mauveglow
    colors[10] = vec3(0.596, 0.651, 0.741); // Pantone 17-4023 Skyway
    colors[11] = vec3(0.945, 0.702, 0.251); // Pantone 14-1064 Vibrant Yellow
    
    int idx = int(mod(floor(value * 12.0), 12.0));
    int nextIdx = int(mod(floor(value * 12.0) + 1.0, 12.0));
    
    // Smooth transition between colors
    float t = fract(value * 12.0);
    t = smoothstep(0.0, 1.0, t); // Smooth transition
    
    return mix(colors[idx], colors[nextIdx], t);
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
        
        // Create a grid effect for color blocks
        float gridSize = 0.15; // Size of color blocks
        vec2 gridPos = floor(v_TexCoord / gridSize);
        
        // Get a random but stable value for this grid position
        float randomValue = random(gridPos);
        
        // Add time-based animation but keep it slow and subtle
        float timeShift = u_Time * 0.05;
        
        // Select pantone color based on grid position and time
        float colorSelection = fract(randomValue + timeShift);
        vec3 pantoneColor = getPantoneColor(colorSelection);
        
        // Apply different color transformations based on brightness
        if (hsv.z > 0.7) {
            // For bright areas - use pantone colors directly with original alpha
            gl_FragColor = vec4(pantoneColor * 1.2, baseColor.a);
        } else if (hsv.z > 0.3) {
            // For mid-tone areas - blend with original but preserve pantone hue
            vec3 blendedColor = mix(baseColor.rgb, pantoneColor, 0.7);
            gl_FragColor = vec4(blendedColor, baseColor.a);
        } else {
            // For darker areas - adjust saturation but keep closer to original
            vec3 darkPantone = pantoneColor * 0.7;
            vec3 blendedDark = mix(baseColor.rgb, darkPantone, 0.5);
            gl_FragColor = vec4(blendedDark, baseColor.a);
        }
        
        // Add subtle pulsing highlight
        float pulse = sin(u_Time * 0.8 + randomValue * 6.28) * 0.5 + 0.5;
        pulse = smoothstep(0.3, 0.7, pulse) * 0.15; // Subtle effect
        
        gl_FragColor.rgb += pantoneColor * pulse;
        
        // Ensure we don't exceed the maximum brightness
        gl_FragColor.rgb = min(gl_FragColor.rgb, vec3(1.0));
    }
    
    // Discard transparent pixels
    if(gl_FragColor.a < 0.01) discard;
} 