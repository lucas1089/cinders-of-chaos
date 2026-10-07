uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Dreamworld parameters
const float BLOOM_STRENGTH = 0.4;           // Strength of the bloom effect
const float PASTEL_INTENSITY = 0.5;         // Intensity of the pastel colors
const float SPARKLE_DENSITY = 0.8;          // Density of the sparkles
const float SPARKLE_SPEED = 0.3;            // Speed of sparkle animation
const float SPARKLE_SIZE = 0.7;             // Size of the sparkles
const vec3 PASTEL_PURPLE = vec3(0.8, 0.6, 0.9);   // Soft purple
const vec3 PASTEL_BLUE = vec3(0.6, 0.8, 0.9);     // Soft blue
const vec3 PASTEL_PINK = vec3(0.95, 0.7, 0.85);   // Soft pink

// Hash function
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// 2D Hash
vec2 hash2D(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
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

// Create sparkles
float sparkles(vec2 position, float time) {
    // Scale position
    vec2 pos = position * 0.05;
    
    // Create a grid of potential sparkle locations
    vec2 id = floor(pos);
    vec2 localPos = fract(pos);
    
    float sparkle = 0.0;
    
    // Check neighboring cells (including current)
    for(int y = -1; y <= 1; y++) {
        for(int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 neighborId = id + offset;
            
            // Get a random position for this cell's sparkle
            vec2 randPoint = hash2D(neighborId);
            
            // Animate sparkle position slightly
            randPoint += sin(time * SPARKLE_SPEED + randPoint * 6.28) * 0.1;
            
            // Distance to the sparkle
            float dist = length(localPos - offset - randPoint);
            
            // Size of this sparkle (random based on cell)
            float size = 0.02 + hash(dot(neighborId, vec2(123.0, 789.0))) * 0.03;
            size *= SPARKLE_SIZE;
            
            // Random sparkle brightness that pulses
            float randBrightness = hash(dot(neighborId, vec2(645.0, 237.0)));
            float pulse = 0.5 + 0.5 * sin(time * 2.0 + randBrightness * 6.28);
            
            // Add this sparkle
            sparkle += smoothstep(size, 0.0, dist) * pulse;
        }
    }
    
    return sparkle * SPARKLE_DENSITY;
}

// Simple bloom effect
vec3 bloomEffect(sampler2D tex, vec2 uv, float radius) {
    vec3 color = vec3(0.0);
    float total = 0.0;
    
    // Simple blur
    for(float x = -4.0; x <= 4.0; x += 1.0) {
        for(float y = -4.0; y <= 4.0; y += 1.0) {
            vec2 sampleUV = uv + vec2(x, y) * radius / u_Resolution;
            float weight = 1.0 - length(vec2(x, y)) / 6.0;
            if(weight > 0.0) {
                color += texture2D(tex, sampleUV).rgb * weight;
                total += weight;
            }
        }
    }
    
    return color / total;
}

void main() {
    // Sample original texture
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    
    // Calculate bloom effect
    vec3 bloom = bloomEffect(u_Tex0, v_TexCoord, 0.01);
    
    // Apply bloom
    color.rgb = mix(color.rgb, bloom, BLOOM_STRENGTH);
    
    // Generate pastel gradient based on position and time
    float noiseVal = fbm(v_WorldPos * 0.01 + u_Time * 0.1);
    vec3 pastelColor = mix(PASTEL_PURPLE, PASTEL_BLUE, sin(noiseVal * 3.14) * 0.5 + 0.5);
    pastelColor = mix(pastelColor, PASTEL_PINK, cos(noiseVal * 3.14) * 0.5 + 0.5);
    
    // Apply pastel colors
    color.rgb = mix(color.rgb, pastelColor, PASTEL_INTENSITY * 0.5);
    
    // Brighten the image slightly
    color.rgb *= 1.2;
    
    // Add dreamworld sparkles
    float sparkle = sparkles(v_WorldPos, u_Time);
    color.rgb += vec3(0.9, 0.9, 1.0) * sparkle;
    
    // Add soft vignette
    vec2 uv = v_TexCoord * 2.0 - 1.0;
    float vignette = 1.0 - dot(uv, uv) * 0.3;
    color.rgb *= vignette;
    
    gl_FragColor = color;
} 