uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Poison parameters
float poisonIntensity = 0.7;       // Overall intensity of poison effect
float mistyGreenness = 0.6;        // How green the poison mist is
float poisonPulseSpeed = 1.2;      // Speed of poison pulsation
float dropSpeed = 0.3;             // Speed of dripping acid
float dropFrequency = 3.0;         // Frequency of drips
float smokeSpeed = 0.2;            // Speed of poison smoke

// Simple noise function
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Fractal noise for mist
float fractalNoise(vec2 p) {
    float f = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    
    for (int i = 0; i < 4; i++) {
        f += amp * noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    
    return f;
}

// Acid drip function
float acidDrip(vec2 uv, float time, float seed) {
    // Starting position for this drip
    float xPos = fract(seed * 3.1415);
    
    // Drip movement - starts at top of sprite and moves down
    float yStart = 1.0 + mod(time * dropSpeed + seed, 1.0);
    float y = yStart - uv.y;
    
    // Drip shape - thin, elongated drops
    float drop = smoothstep(0.01, 0.0, abs(uv.x - xPos) - 0.005 * (1.0 - y));
    drop *= smoothstep(0.1, 0.0, y) * smoothstep(0.0, 0.1, y + 0.1);
    
    // Add drip trail that fades out
    float trail = smoothstep(0.005, 0.0, abs(uv.x - xPos) - 0.002); 
    trail *= smoothstep(0.0, 1.0, yStart - uv.y) * smoothstep(1.0, 0.0, (yStart - uv.y) * 5.0);
    
    return drop + trail * 0.2;
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
    
    // Start with original color
    vec4 resultColor = baseColor;
    
    // Calculate poisonous green factor with pulsation
    float pulse = 0.7 + 0.3 * sin(u_Time * poisonPulseSpeed);
    
    // Poison green values
    vec3 poisonColor = vec3(0.2, 0.8, 0.1); // Bright toxic green
    vec3 darkPoisonColor = vec3(0.1, 0.4, 0.05); // Darker toxic green
    
    // Generate poison mist texture
    vec2 mistUV = v_TexCoord3 * 2.0 + vec2(u_Time * 0.1, u_Time * smokeSpeed);
    float mist = fractalNoise(mistUV);
    
    // Add some movement to the mist
    mist += 0.3 * fractalNoise(mistUV * 2.0 - vec2(u_Time * 0.2, 0.0));
    
    // Create edge factor to have more mist around the edges
    float edgeFactor = 1.0 - smoothstep(0.4, 0.7, baseColor.a);
    
    // Create acid drip effect
    float drips = 0.0;
    for (int i = 0; i < 4; i++) {
        float seed = float(i) / 4.0;
        drips += acidDrip(v_TexCoord3, u_Time * (0.5 + seed * 0.5) + seed * 10.0, seed);
    }
    
    // Apply drip coloring
    resultColor.rgb = mix(resultColor.rgb, poisonColor, drips * pulse * poisonIntensity);
    
    // Apply poison mist using edge factor
    float mistFactor = mist * edgeFactor * pulse * mistyGreenness;
    resultColor.rgb = mix(resultColor.rgb, poisonColor, mistFactor);
    
    // Add subtle overall green tint based on pulsation
    resultColor.rgb = mix(resultColor.rgb, darkPoisonColor, pulse * 0.2 * poisonIntensity);
    
    // Add bright green highlights to give acidic feel
    resultColor.rgb += poisonColor * drips * pulse * 0.5;
    
    // Output
    gl_FragColor = resultColor;
} 