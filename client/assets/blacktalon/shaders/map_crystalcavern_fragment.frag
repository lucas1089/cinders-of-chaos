uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Crystal cavern parameters
const float CRYSTAL_OPACITY = 0.6;          // Strength of crystal overlay
const float SPARKLE_DENSITY = 0.7;          // Density of sparkles
const float SPARKLE_SIZE = 0.6;             // Size of sparkles
const float REFRACTION_STRENGTH = 0.3;      // Strength of prismatic refraction
const float RAINBOW_INTENSITY = 0.3;        // Intensity of rainbow colors
const float BRIGHTNESS_BOOST = 0.2;         // Overall brightness increase

// Hash function
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// 2D hash
vec2 hash2D(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// Return a rainbow color based on value in [0,1]
vec3 rainbow(float t) {
    vec3 c = 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
    c = c * c; // Make colors more vibrant
    return c;
}

// Crystal structure noise
float crystalNoise(vec2 p, float time) {
    // Create angular crystal-like pattern
    float angle = atan(p.y, p.x);
    float radius = length(p);
    
    // Create radial segments
    float segments = 6.0 + floor(radius * 0.5);
    float segmentAngle = 6.28318 / segments;
    float angleFract = mod(angle, segmentAngle) / segmentAngle;
    
    // Create gradient along segment
    float gradient = abs(angleFract - 0.5) * 2.0;
    gradient = pow(gradient, 2.0); // Sharpen edges
    
    // Add noise to break up the pattern
    float noise = hash(radius * 10.0 + angle * 20.0 + time * 0.1);
    
    // Combine for crystal-like structure
    return gradient * (0.7 + noise * 0.3);
}

// Create sparkles
float sparkles(vec2 position, float time) {
    // Scale position
    vec2 pos = position * 0.03;
    
    // Create a grid of potential sparkle locations
    vec2 id = floor(pos);
    vec2 localPos = fract(pos);
    
    float sparkle = 0.0;
    
    // Check neighboring cells
    for(int y = -1; y <= 1; y++) {
        for(int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 neighborId = id + offset;
            
            // Get a random position for this cell's sparkle
            vec2 randPoint = hash2D(neighborId);
            
            // Animate sparkle position slightly
            randPoint += sin(time * 0.5 + randPoint * 6.28) * 0.1;
            
            // Distance to the sparkle
            float dist = length(localPos - offset - randPoint);
            
            // Size of this sparkle (random based on cell)
            float size = 0.01 + hash(dot(neighborId, vec2(123.0, 789.0))) * 0.02;
            size *= SPARKLE_SIZE;
            
            // Random sparkle brightness that pulses based on position
            float randBrightness = hash(dot(neighborId, vec2(645.0, 237.0)));
            float pulse = 0.5 + 0.5 * sin(time * 3.0 + randBrightness * 6.28);
            pulse = pulse * pulse; // Sharpen pulse
            
            // Add this sparkle
            sparkle += smoothstep(size, 0.0, dist) * pulse;
        }
    }
    
    return sparkle * SPARKLE_DENSITY;
}

// Apply prismatic refraction
vec3 prismaticRefraction(sampler2D tex, vec2 uv, vec2 worldPos, float time) {
    // Create base crystal direction
    float angle = atan(worldPos.y, worldPos.x);
    float radius = length(worldPos) * 0.01;
    
    // Create direction for sampling
    vec2 dir = vec2(cos(angle + time * 0.2), sin(angle + time * 0.2)) * 0.0015;
    
    // Sample the texture with rgb shift (prismatic effect)
    vec3 color;
    
    // Sample red channel shifted one way
    color.r = texture2D(tex, uv + dir * REFRACTION_STRENGTH).r;
    
    // Sample green channel with no shift
    color.g = texture2D(tex, uv).g;
    
    // Sample blue channel shifted the other way
    color.b = texture2D(tex, uv - dir * REFRACTION_STRENGTH).b;
    
    return color;
}

void main() {
    // Sample original texture with prismatic refraction
    vec3 refractedColor = prismaticRefraction(u_Tex0, v_TexCoord, v_WorldPos, u_Time);
    vec4 color = vec4(refractedColor, 1.0);
    
    // Calculate crystal pattern
    float crystal = crystalNoise(v_WorldPos * 0.005, u_Time);
    
    // Add rainbow color modulation
    float rainbowPhase = crystal + u_Time * 0.1;
    vec3 rainbowColor = rainbow(rainbowPhase);
    
    // Apply crystal effect with rainbow
    color.rgb = mix(color.rgb, color.rgb * rainbowColor * 1.5, crystal * CRYSTAL_OPACITY * RAINBOW_INTENSITY);
    
    // Add sparkles
    float sparkle = sparkles(v_WorldPos, u_Time);
    color.rgb += rainbowColor * sparkle * 2.0;
    
    // Add overall brightness boost
    color.rgb += vec3(BRIGHTNESS_BOOST) * crystal;
    
    // Add subtle shimmering highlights
    float shimmer = sin(v_WorldPos.x * 0.05 + v_WorldPos.y * 0.03 + u_Time * 2.0) * 0.5 + 0.5;
    shimmer = pow(shimmer, 4.0); // Make shimmer more focused
    color.rgb += rainbowColor * shimmer * 0.2;
    
    gl_FragColor = color;
} 