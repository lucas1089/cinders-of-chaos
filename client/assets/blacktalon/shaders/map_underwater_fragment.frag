uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Underwater parameters
const vec3 WATER_COLOR = vec3(0.0, 0.4, 0.8);    // Deep blue tint
const float WATER_OPACITY = 0.4;                  // How strong the water color is
const float WAVE_SPEED = 0.2;                     // Slow wave speed to prevent jittering
const float DISTORTION_STRENGTH = 0.005;          // Subtle wave distortion
const float CAUSTICS_INTENSITY = 0.12;            // Light patterns intensity
const float BUBBLE_DENSITY = 0.8;                 // Amount of bubbles
const float BLUR_STRENGTH = 0.15;                 // Edge blur amount

// Hash function
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// 2D noise
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

// Underwater distortion - fixed to screen space
vec2 waterDistortion(vec2 uv, vec2 worldPos, float time) {
    vec2 distortion = vec2(0.0);
    
    // Use screen-relative coordinates instead of world position
    vec2 normalizedCoord = uv * 10.0;
    
    // Small waves - primarily based on screen position with minimal time factor
    float smallWaves = sin(normalizedCoord.x * 7.0 + normalizedCoord.y * 9.0 + time * 0.5) +
                      cos(normalizedCoord.y * 8.0 + normalizedCoord.x * 6.0 + time * 0.4);
                      
    // Medium waves
    float mediumWaves = sin(normalizedCoord.x * 3.5 + normalizedCoord.y * 4.0 + time * 0.3) +
                       cos(normalizedCoord.y * 4.5 + normalizedCoord.x * 3.0 + time * 0.2);
    
    // Large waves - very slow movement
    float largeWaves = sin(normalizedCoord.x * 1.5 + normalizedCoord.y * 2.0 + time * 0.1) +
                      cos(normalizedCoord.y * 2.0 + normalizedCoord.x * 1.0 + time * 0.08);
    
    // Combine waves at different scales
    distortion.x = (smallWaves * 0.2 + mediumWaves * 0.3 + largeWaves * 0.5) * DISTORTION_STRENGTH;
    distortion.y = (smallWaves * 0.3 + mediumWaves * 0.4 + largeWaves * 0.3) * DISTORTION_STRENGTH;
    
    return distortion;
}

// Bubble function
float bubble(vec2 uv, float time, float size, float speed) {
    // Move bubbles upwards
    uv.y -= time * speed;
    
    // Create grid for bubbles
    vec2 gridPos = fract(uv * size);
    vec2 id = floor(uv * size);
    
    // Random position within cell
    vec2 cellPos = vec2(
        0.5 + 0.4 * sin(hash(id.x + id.y * 57.0) * 6.28),
        0.5 + 0.4 * sin(hash(id.y + id.x * 73.0) * 6.28)
    );
    
    // Random bubble size
    float bubbleSize = 0.02 + 0.03 * hash(id.x * 33.3 + id.y * 77.7);
    
    // Wobble bubble position
    cellPos.x += 0.1 * sin(time * 2.0 + hash(id.y) * 6.28);
    
    // Distance from grid position to cell position
    float dist = distance(gridPos, cellPos);
    
    // Create bubble with soft edge
    return smoothstep(bubbleSize, bubbleSize - 0.01, dist);
}

// Light caustics effect (rippling light patterns)
float caustics(vec2 uv, float time) {
    // Use screen-space coordinates for stability
    vec2 stableCoord = uv * 15.0;
    
    // Multiple layers of sin waves at different frequencies
    float val = 0.0;
    val += 0.5 * sin(stableCoord.x * 2.0 + stableCoord.y * 1.0 + time * 0.4);
    val += 0.25 * sin(stableCoord.x * 3.0 - stableCoord.y * 1.5 + time * 0.3);
    val += 0.125 * sin(stableCoord.x * 4.0 + stableCoord.y * 2.5 + time * 0.5);
    val = 0.5 + 0.5 * val;
    
    return smoothstep(0.4, 0.6, val);
}

// Simple blur function
vec4 simpleBlur(sampler2D tex, vec2 uv, float strength) {
    vec4 color = vec4(0.0);
    float totalWeight = 0.0;
    
    // Very small 3x3 kernel blur
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
    // Animated time
    float time = u_Time * WAVE_SPEED;
    
    // Get water distortion vector (based on screen coordinates for stability)
    vec2 distortion = waterDistortion(v_TexCoord, v_WorldPos, time);
    
    // Sample texture with distortion and subtle blur
    vec4 color = simpleBlur(u_Tex0, v_TexCoord + distortion, BLUR_STRENGTH);
    
    // Add light caustics effect
    float causticEffect = caustics(v_TexCoord, time);
    color.rgb += causticEffect * CAUSTICS_INTENSITY;
    
    // Add blue water tint
    color.rgb = mix(color.rgb, WATER_COLOR, WATER_OPACITY);
    
    // Generate bubbles - use screen space for stability
    float bubbles = 0.0;
    bubbles += bubble(v_TexCoord * 20.0, time, 8.0, 0.1);
    bubbles += bubble(v_TexCoord * 30.0, time * 0.8, 12.0, 0.2) * 0.7;
    bubbles += bubble(v_TexCoord * 40.0, time * 1.2, 16.0, 0.3) * 0.5;
    bubbles = min(bubbles, 1.0) * BUBBLE_DENSITY;
    
    // Add bubbles to final image
    color.rgb += vec3(bubbles) * 0.3;
    
    // Slight darkening (water absorbs light)
    color.rgb *= 0.85;
    
    gl_FragColor = color;
} 