uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_Time;

// Drunk parameters for map
float waveSpeed = 0.8;
float waveIntensity = 0.02;
float distortionStrength = 0.01;
float colorShiftAmount = 0.1;

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
    
    for(int i = 0; i < 4; i++) {
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
    distortion.x = sin(time + v_TexCoord.y * 8.0) * distortionStrength;
    distortion.y = cos(time * 0.7 + v_TexCoord.x * 6.0) * distortionStrength;
    
    // Add noise-based distortion
    vec2 noiseCoord = vec2(
        v_TexCoord.x + time * 0.1,
        v_TexCoord.y + time * 0.2
    );
    float noiseVal = fbm(noiseCoord * 4.0);
    distortion += vec2(noiseVal - 0.5) * distortionStrength * 1.5;
    
    // Sample with distortion
    vec2 distortedCoord = v_TexCoord + distortion;
    vec4 color = texture2D(u_Tex0, distortedCoord);
    
    // Add chromatic aberration (color separation)
    vec4 colorR = texture2D(u_Tex0, distortedCoord + vec2(distortionStrength * 0.5, 0.0));
    vec4 colorB = texture2D(u_Tex0, distortedCoord - vec2(distortionStrength * 0.5, 0.0));
    
    // Combine for color fringing effect
    color.r = mix(color.r, colorR.r, 0.5);
    color.b = mix(color.b, colorB.b, 0.5);
    
    // Add subtle color shift
    float colorShift = sin(time * 0.5) * colorShiftAmount;
    color.r += colorShift * 0.1;
    color.g -= colorShift * 0.05;
    color.b += colorShift * 0.15;
    
    // Slightly reduce saturation
    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, vec3(luminance), 0.1);
    
    // Output final color
    gl_FragColor = color;
} 