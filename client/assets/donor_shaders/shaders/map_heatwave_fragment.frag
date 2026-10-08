uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Heat haze parameters
const float HAZE_SPEED = 0.15;         // Reduced speed for more subtle effect
const float HAZE_INTENSITY = 0.003;    // Reduced distortion strength
const float HAZE_FREQUENCY = 10.0;     // Slightly reduced frequency for gentler waves
const vec3 HEAT_TINT = vec3(1.03, 1.0, 0.97); // More subtle warm tint

// Noise function
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    // Add several octaves of noise
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

void main() {
    // Animated time
    float time = u_Time * HAZE_SPEED;
    
    // Calculate distortion based on horizontal waves and time
    vec2 distortion;
    
    // Primary horizontal ripple effect
    distortion.x = sin(v_WorldPos.y * HAZE_FREQUENCY + time * 1.5) * HAZE_INTENSITY;
    
    // Secondary ripples for more natural look
    distortion.x += sin(v_WorldPos.y * HAZE_FREQUENCY * 0.5 + time * 0.8) * HAZE_INTENSITY * 0.5;
    
    // Small vertical distortion
    distortion.y = sin(v_WorldPos.x * HAZE_FREQUENCY * 0.2 + time * 0.7) * HAZE_INTENSITY * 0.2;
    
    // Noise-based distortion to create shimmering
    vec2 noiseSample = vec2(
        v_WorldPos.x * 0.05 + time * 0.05,
        v_WorldPos.y * 0.05 + time * 0.1
    );
    float noiseVal = fbm(noiseSample) - 0.5;
    distortion += vec2(noiseVal) * HAZE_INTENSITY * 0.6;
    
    // Apply distortion with distance-based falloff (stronger at bottom of screen)
    float groundEffect = smoothstep(0.2, 1.0, v_TexCoord.y);
    distortion *= groundEffect;
    
    // Sample texture with distortion
    vec2 distortedUV = v_TexCoord + distortion;
    vec4 color = texture2D(u_Tex0, distortedUV);
    
    // Add subtle warm tint
    color.rgb *= HEAT_TINT;
    
    // Add slight brightness variation to simulate heat shimmer
    float shimmer = sin(time * 2.0 + v_WorldPos.y * 2.0) * 0.02;
    color.rgb += shimmer * groundEffect;
    
    gl_FragColor = color;
} 