uniform mat4 u_Color;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform float u_Time;

varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
varying vec4 v_Color;

// Pseudo-random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Improved noise function for crystalline patterns
float crystalNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    
    // Cubic interpolation
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    // Mix 4 corners
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Voronoi pattern for crystalline borders
float voronoi(vec2 uv, float scale) {
    uv *= scale;
    vec2 i_uv = floor(uv);
    vec2 f_uv = fract(uv);
    
    float minDist = 1.0;
    vec2 minPoint;
    
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            float rnd = random(i_uv + neighbor);
            vec2 point = vec2(rnd, rnd) * 0.5 + 0.25;
            
            // Animate the points
            point = 0.5 + 0.5 * sin(u_Time * 0.5 + 6.2831 * point);
            
            vec2 diff = neighbor + point - f_uv;
            float dist = length(diff);
            
            if (dist < minDist) {
                minDist = dist;
                minPoint = point;
            }
        }
    }
    
    return minDist;
}

void main()
{
    // Sample the original texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample both trippy textures
    vec4 texture1 = texture2D(u_Tex1, v_TexCoord3);
    vec4 texture2 = texture2D(u_Tex2, v_TexCoord4);
    
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
        // Create crystalline facets with molten edges
        float crystalPattern = voronoi(v_TexCoord * 4.0, 3.0 + sin(u_Time * 0.2) * 0.5);
        float edgeGlow = smoothstep(0.05, 0.2, crystalPattern);
        
        // Pixelate the texture coordinates for crystalline blocks
        vec2 pixelSize = vec2(0.033, 0.033); // Controls crystal facet size
        vec2 pixelatedCoord = floor(v_TexCoord / pixelSize) * pixelSize;
        
        // Get noise value for each pixel block
        float pixelNoise = crystalNoise(pixelatedCoord * 20.0 + u_Time * 0.1);
        
        // Create the battle between textures - use crystal structure to define domains
        float domainPattern = step(0.5, crystalNoise(pixelatedCoord * 5.0 + sin(u_Time * 0.3) * 0.2));
        
        // Animate the crystal growth/melting at the boundaries
        float growthFactor = sin(u_Time * 0.5 + pixelatedCoord.x * 10.0 + pixelatedCoord.y * 8.0) * 0.1;
        domainPattern = smoothstep(0.45 + growthFactor, 0.55 + growthFactor, domainPattern);
        
        // Blend textures based on domain
        vec3 blendedTexture = mix(texture1.rgb, texture2.rgb, domainPattern);
        
        // Add pixelated glitter effect
        vec2 sparkleGrid = floor(v_TexCoord * 50.0) / 50.0; // More pixelated
        float sparkleRandom = random(sparkleGrid + floor(u_Time * 5.0)); // More quantized time
        
        if (sparkleRandom > 0.65) {
            float blinkRate = floor(u_Time * 4.0) * 0.25; // Quantized blink rate for pixel feel
            float sparkleIntensity = step(0.5, sin(blinkRate + sparkleRandom * 100.0));
            
            // Crystal color highlights based on domain
            vec3 sparkleColor = domainPattern > 0.5 ? 
                vec3(0.2, 0.8, 1.0) : // Blue/cyan for cool crystal regions
                vec3(1.0, 0.5, 0.2);  // Orange/amber for hot regions
            
            // Add more intense sparkle at crystal edges
            float edgeIntensity = 1.0 - smoothstep(0.0, 0.3, crystalPattern);
            sparkleIntensity *= (1.0 + edgeIntensity * 2.0);
            
            blendedTexture += sparkleColor * sparkleIntensity * 0.8 * step(0.2, pixelNoise);
        }
        
        // Add molten glow at the boundaries between crystal domains
        float boundaryWidth = 0.15;
        float boundary = abs(domainPattern - 0.5);
        if (boundary < boundaryWidth) {
            float moltenIntensity = (boundaryWidth - boundary) / boundaryWidth;
            moltenIntensity = pow(moltenIntensity, 2.0);
            
            // Quantized oscillation for pixelated feel
            float pulseRate = floor(u_Time * 3.0) * 0.33;
            float pulse = step(0.5, sin(pulseRate * 6.28));
            
            // Add molten glow (orange-red)
            blendedTexture += vec3(1.5, 0.4, 0.1) * moltenIntensity * (0.5 + pulse * 0.5);
        }
        
        // Mix with base color
        vec3 finalColor = mix(baseColor.rgb, blendedTexture, 0.85);
        
        // Add crystal edge highlights
        finalColor += vec3(0.8, 0.8, 1.0) * pow(1.0 - edgeGlow, 3.0) * 0.5;
        
        // Ensure we don't exceed maximum brightness
        finalColor = min(finalColor, vec3(1.0));
        
        gl_FragColor = vec4(finalColor, baseColor.a);
    }
    
    // Discard transparent pixels
    if(gl_FragColor.a < 0.01) discard;
} 