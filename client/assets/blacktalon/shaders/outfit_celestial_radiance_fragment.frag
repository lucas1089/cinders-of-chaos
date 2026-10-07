uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Celestial parameters
float starDensity = 20.0;       // How many stars
float starBrightness = 0.8;     // Star brightness
float nebulaBrightness = 0.4;   // Nebula cloud brightness
float parallaxSpeed = 0.05;     // Speed of star movement
float twinkleSpeed = 1.0;       // Speed of star twinkling
float bgOpacity = 0.65;         // Opacity of celestial overlay

// Star creation function
float star(vec2 uv, float flare) {
    float d = length(uv);
    float m = 0.05 / d;
    
    float rays = max(0.0, 1.0 - abs(uv.x * uv.y * 1000.0));
    
    // Create star with rays
    m += rays * flare;
    m *= smoothstep(1.0, 0.2, d);
    
    return m;
}

// Random function for star distribution
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// 2D Noise for nebula
float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    
    // Four corners in 2D
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    
    // Smooth interpolation
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(a, b, u.x) + 
            (c - a) * u.y * (1.0 - u.x) + 
            (d - b) * u.x * u.y;
}

// Fractal noise for nebula clouds
float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    // Octaves of noise
    for (int i = 0; i < 6; i++) {
        value += amplitude * noise(st * frequency);
        st = st * 2.0 + 0.05; // Rotate to reduce axial bias
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

void main() {
    // Sample original texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Skip processing completely transparent pixels
    if(baseColor.a < 0.01) discard;
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Get normalized UV coordinates from vertex shader
    vec2 uv = v_TexCoord3;
    
    // Calculate parallax movement based on time
    vec2 parallaxOffset = vec2(u_Time * parallaxSpeed * 0.1, u_Time * parallaxSpeed * 0.2);
    
    // Create starfield
    vec3 stars = vec3(0.0);
    
    // Generate multiple layers of stars with different movement speeds
    for (int i = 0; i < 3; i++) {
        float layerSpeed = float(i) * 0.5 + 0.5;
        vec2 layerOffset = parallaxOffset * layerSpeed;
        
        // Create star grid
        for (int y = 0; y < 5; y++) {
            for (int x = 0; x < 5; x++) {
                // Create star grid pattern
                vec2 starPos = vec2(float(x), float(y)) / starDensity;
                
                // Add randomization to star positions
                starPos += vec2(
                    random(vec2(float(x) * 0.11, float(y) * 0.17)) * 0.07,
                    random(vec2(float(y) * 0.11, float(x) * 0.17)) * 0.07
                );
                
                // Calculate star UV position with parallax
                vec2 starUV = uv - starPos - layerOffset;
                
                // Add time-based twinkling
                float brightness = 0.5 + 0.5 * sin(u_Time * twinkleSpeed + float(x*y) * 0.1);
                brightness = pow(brightness, 2.0) * 0.8 + 0.2;
                
                // Generate star with flare
                float flare = random(starPos) * brightness;
                float s = star(starUV, flare) * brightness * starBrightness;
                
                // Star color based on randomness and layer
                vec3 starColor = mix(
                    vec3(0.6, 0.8, 1.0),  // Blue-white
                    vec3(1.0, 0.6, 0.5),  // Red-orange
                    random(starPos * 10.0 + float(i))
                );
                
                // Add star to result
                stars += s * starColor * (0.5 + float(i) * 0.25);
            }
        }
    }
    
    // Create nebula effect
    vec2 nebulaUV = uv * 1.5 + parallaxOffset * 0.2;
    float nebula = fbm(nebulaUV);
    
    // Create color variation in nebula
    vec3 nebulaColor1 = vec3(0.1, 0.2, 0.6); // Deep blue
    vec3 nebulaColor2 = vec3(0.6, 0.1, 0.4); // Purple
    vec3 nebulaColor = mix(nebulaColor1, nebulaColor2, fbm(nebulaUV * 2.0 + 0.5));
    
    // Add nebula to stars, only where the nebula is dense enough
    nebulaColor *= smoothstep(0.1, 0.6, nebula) * nebulaBrightness;
    
    // Mix celestial effect with base color
    vec3 celestialEffect = stars + nebulaColor;
    
    // Create final result - blend celestial effect over the original texture
    gl_FragColor = baseColor;
    
    // Only show celestial effect on non-transparent parts
    if (baseColor.a > 0.3) {
        gl_FragColor.rgb = mix(gl_FragColor.rgb, celestialEffect, bgOpacity);
        
        // Add a bit of color tint from stars/nebula
        gl_FragColor.rgb += celestialEffect * 0.2;
    }
} 