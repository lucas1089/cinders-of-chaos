uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Drunk parameters
float waveSpeed = 1.2;
float waveIntensity = 0.03;
float distortionStrength = 0.015;

// Noise function for the drunk effect
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 57.0;
    return mix(
        mix(hash(n), hash(n + 1.0), f.x),
        mix(hash(n + 57.0), hash(n + 58.0), f.x),
        f.y
    );
}

// FBM (Fractal Brownian Motion) for drunk distortion
float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    
    for(int i = 0; i < 3; i++) {
        sum += amp * noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
        p = vec2(p.y - sum * 0.1, p.x);
    }
    
    return sum;
}

void main() {
    // Animated time
    float time = u_Time * waveSpeed;
    
    // Create distortion offset
    vec2 distortion;
    distortion.x = sin(time + v_TexCoord.y * 10.0) * distortionStrength;
    distortion.y = cos(time * 0.7 + v_TexCoord.x * 8.0) * distortionStrength;
    
    // Add noise-based distortion
    vec2 noiseCoord = vec2(
        v_TexCoord.x + time * 0.1,
        v_TexCoord.y + time * 0.2
    );
    float noiseVal = fbm(noiseCoord * 5.0);
    distortion += vec2(noiseVal - 0.5) * distortionStrength * 2.0;
    
    // Apply distortion to texture coordinates
    vec2 distortedCoord = v_TexCoord + distortion;
    
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, distortedCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Set output color
    gl_FragColor = baseColor;
    
    // Add subtle color shift
    float colorShift = sin(time * 0.5) * 0.1;
    gl_FragColor.r += colorShift;
    gl_FragColor.b -= colorShift;
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 