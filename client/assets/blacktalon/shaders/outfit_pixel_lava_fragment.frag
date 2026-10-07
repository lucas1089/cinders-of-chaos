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

// Pseudo-random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Cellular noise (for lava-like borders)
float cellular(vec2 uv, float scale) {
    uv *= scale;
    vec2 i_uv = floor(uv);
    vec2 f_uv = fract(uv);
    
    float minDist = 1.0;
    
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = vec2(float(x), float(y));
            float rnd = random(i_uv + neighbor);
            vec2 point = vec2(rnd, rnd) * 0.5 + 0.5;
            point = 0.5 + 0.5 * sin(u_Time * 0.8 + 6.2831 * point);
            vec2 diff = neighbor + point - f_uv;
            float dist = length(diff);
            minDist = min(minDist, dist);
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
        // Create lava-like border effect
        float cellNoise = cellular(v_TexCoord * 2.0, 4.0);
        float lavaBorder = smoothstep(0.2, 0.4, cellNoise);
        
        // Oscillate the blend boundary
        float edge = sin(v_TexCoord.y * 15.0 + u_Time * 1.5) * 0.15 + 0.5;
        
        // Create pixelated regions
        vec2 pixelGrid = floor(v_TexCoord * 30.0) / 30.0; // Adjust 30.0 to control pixelation
        float pixelNoise = random(pixelGrid + u_Time * 0.05);
        
        // Combine noise with cellular pattern for dynamic lava flow
        float lavaFlow = smoothstep(0.3, 0.7, lavaBorder + (sin(u_Time * 0.5) * 0.2 + pixelNoise * 0.3));
        
        // Select texture based on lava flow pattern
        vec3 blendedTexture = mix(texture1.rgb, texture2.rgb, lavaFlow);
        
        // Add pixelated glitter effect
        vec2 sparkleGrid = floor(v_TexCoord * 40.0) / 40.0; // Larger grid for more pixelated effect
        float sparkleRandom = random(sparkleGrid);
        
        if (sparkleRandom > 0.7) {
            float sparkleIntensity = sin(u_Time * (3.0 + sparkleRandom * 2.0)) * 0.5 + 0.5;
            sparkleIntensity = pow(sparkleIntensity, 3.0) * 1.2;
            
            if (sparkleIntensity > 0.3) {
                // Add pixelated sparkles (with color tint based on which texture dominates)
                vec3 sparkleColor = lavaFlow > 0.5 ? 
                    vec3(1.5, 0.9, 0.3) : // Golden/orange for texture2 regions
                    vec3(0.9, 0.3, 0.1);  // Red/fire for texture1 regions
                
                blendedTexture += sparkleColor * sparkleIntensity * 0.7;
            }
        }
        
        // Apply heat shimmer effect at texture boundaries
        if (abs(lavaFlow - 0.5) < 0.15) {
            float shimmer = sin(v_TexCoord.y * 40.0 + u_Time * 5.0) * 0.15;
            blendedTexture.r += shimmer;
            blendedTexture.b -= shimmer * 0.5;
        }
        
        // Mix with base color
        vec3 finalColor = mix(baseColor.rgb, blendedTexture, 0.85);
        
        // Add general glow and brightness
        finalColor += blendedTexture * 0.2;
        finalColor = min(finalColor, vec3(1.0));
        
        gl_FragColor = vec4(finalColor, baseColor.a);
    }
    
    // Discard transparent pixels
    if(gl_FragColor.a < 0.01) discard;
} 