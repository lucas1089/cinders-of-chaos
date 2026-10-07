uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Frozen parameters
const vec3 ICE_COLOR = vec3(0.7, 0.8, 0.95);     // Frosty blue
const vec3 FROST_COLOR = vec3(0.9, 0.95, 1.0);   // White-blue frost
const float ICE_OPACITY = 0.5;                   // Strength of ice effect
const float FROST_OPACITY = 0.15;                // Strength of frost overlay
const float EDGE_WIDTH = 0.3;                    // Width of edge frost (increased from 0.15)
const float EDGE_MAX_OPACITY = 0.5;              // Maximum opacity at edges (reduced from 0.7)
const float CRACK_INTENSITY = 0.04;              // Intensity of ice cracks
const float CRACK_SCALE = 2.0;                   // Scale of crack pattern
const float CRACK_SPEED = 0.02;                  // Speed of crack animation
const float DISTORTION_STRENGTH = 0.003;         // How much the ice distorts view
const float BLUR_STRENGTH = 0.1;                 // Slight ice blur amount

// Hash function
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// 2D Noise
float noise2d(vec2 p) {
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

// Fractal Brownian Motion
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    // Add octaves of noise
    for(int i = 0; i < 4; i++) {
        value += amplitude * noise2d(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// Ice distortion effect - screen space based for stability
vec2 iceDistortion(vec2 uv) {
    // Use screen-space coordinates to prevent jumping
    vec2 distortion = vec2(0.0);
    
    // Create purely screen-space based distortion with no time component
    // This prevents jittering when moving
    float xDistort = sin(uv.x * 15.0 + uv.y * 10.0) * 0.5;
    xDistort += sin(uv.x * 30.0 + uv.y * 25.0) * 0.25;
    
    float yDistort = cos(uv.y * 12.0 + uv.x * 18.0) * 0.5;
    yDistort += cos(uv.y * 25.0 + uv.x * 28.0) * 0.25;
    
    // Add minimal time-based movement
    // Very slow and subtle to avoid noticeable jumping
    float timeScale = 0.01;
    xDistort += sin(uv.y * 8.0 + u_Time * timeScale) * 0.1;
    yDistort += cos(uv.x * 9.0 + u_Time * timeScale) * 0.1;
    
    distortion.x = xDistort * DISTORTION_STRENGTH;
    distortion.y = yDistort * DISTORTION_STRENGTH;
    
    return distortion;
}

// Ice cracks pattern
float iceCracks(vec2 p, float time) {
    // Use screen-space for stability with slight influence from world position
    vec2 stableCoord = v_TexCoord * 20.0 + v_WorldPos * 0.001;
    
    // Base noise for crack pattern
    float cracks = fbm(stableCoord * CRACK_SCALE);
    
    // Animate cracks very slowly
    cracks += fbm(stableCoord * CRACK_SCALE * 2.0 + vec2(time * CRACK_SPEED)) * 0.5;
    
    // Make cracks look like veins with thresholding
    cracks = smoothstep(0.7, 0.75, cracks);
    
    return cracks * CRACK_INTENSITY;
}

// Edge frost pattern - modified to extend beyond screen borders and have softer falloff
float edgeFrost(vec2 uv) {
    // Scale UV to create extended frost area (-0.5 to 1.5 instead of 0 to 1)
    // This creates frost that extends beyond the visible screen
    vec2 extendedUV = uv * 2.0 - 1.0;
    
    // Calculate distance from center, but with a softer profile that extends beyond screen
    float distFromCenter = length(extendedUV) * 0.85; // Scaled down to reduce intensity
    
    // Create softer transition with extended range
    // Now frost starts earlier (at 1.0 - EDGE_WIDTH) and extends beyond screen borders
    float edgePower = smoothstep(1.0 - EDGE_WIDTH, 1.3, distFromCenter);
    
    // Add noise to make edges more natural - screen-space based
    vec2 noiseCoord = uv * 10.0;
    float noise = fbm(noiseCoord);
    
    // Add variation to edge power based on noise
    edgePower *= 0.8 + noise * 0.4;
    
    // Cap the maximum edge power to avoid too strong effect at corners
    return min(edgePower, 0.85);
}

// Main frost overlay - mix of screen and world space for detail without jitter
float frostPattern(vec2 texCoord, vec2 worldPos) {
    // Use primarily screen-space for stability
    vec2 stableCoord = texCoord * 10.0;
    
    // Add subtle world-space detail
    stableCoord += worldPos * 0.001;
    
    // Create frost with varying scales
    float frost = 0.0;
    frost += noise2d(stableCoord * 0.5) * 0.5;
    frost += noise2d(stableCoord * 1.0) * 0.3;
    frost += noise2d(stableCoord * 2.0) * 0.2;
    
    return frost;
}

// Simple blur for frosted glass look
vec4 simpleBlur(sampler2D tex, vec2 uv, float strength) {
    vec4 color = vec4(0.0);
    float totalWeight = 0.0;
    
    // Small 3x3 kernel blur
    for (float x = -1.0; x <= 1.0; x += 1.0) {
        for (float y = -1.0; y <= 1.0; y += 1.0) {
            vec2 offset = vec2(x, y) * strength / u_Resolution;
            float weight = (1.0 - abs(x) * 0.33) * (1.0 - abs(y) * 0.33);
            color += texture2D(tex, uv + offset) * weight;
            totalWeight += weight;
        }
    }
    
    return color / totalWeight;
}

void main() {
    // Get ice distortion vector (screen-space based)
    vec2 distortion = iceDistortion(v_TexCoord);
    
    // Sample texture with distortion and slight blur for frosted glass effect
    vec4 color = simpleBlur(u_Tex0, v_TexCoord + distortion, BLUR_STRENGTH);
    
    // Create frost pattern for overlay - mix screen and world space
    float frost = frostPattern(v_TexCoord, v_WorldPos);
    
    // Create edge frost for screen borders with extended range
    float edge = edgeFrost(v_TexCoord);
    
    // Create ice cracks
    float cracks = iceCracks(v_WorldPos, u_Time);
    
    // Apply frosty blue tint
    color.rgb = mix(color.rgb, ICE_COLOR, ICE_OPACITY);
    
    // Add frost overlay
    color.rgb = mix(color.rgb, FROST_COLOR, frost * FROST_OPACITY);
    
    // Add ice cracks (darker lines)
    color.rgb *= 1.0 - cracks;
    
    // Add edge frost effect with reduced opacity
    color.rgb = mix(color.rgb, FROST_COLOR, edge * EDGE_MAX_OPACITY);
    
    // Add slight desaturation
    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, vec3(luminance), 0.2);
    
    gl_FragColor = color;
} 