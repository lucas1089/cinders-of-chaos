uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Sandstorm parameters
const float SAND_SPEED = 2.2;              // Increased speed for more noticeable movement
const float SAND_DENSITY = 0.7;            // Overall amount of sand particles
const vec3 SAND_COLOR = vec3(0.83, 0.65, 0.33); // Sandy brown color
const vec3 DUST_COLOR = vec3(0.76, 0.6, 0.35);  // Dust color
const float DIRECTION_X = -1.0;            // Direction multiplier (-1 for left, 1 for right)

// Hash function
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// Noise function
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

// FBM (Fractal Brownian Motion) for dust clouds
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    // Add several layers of noise
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// Sand particle function
float sandParticle(vec2 uv, float size, float time) {
    // Move sand particles horizontally with diagonal drift
    uv.x += time * SAND_SPEED * DIRECTION_X;
    uv.y += time * SAND_SPEED * 0.3;  // Increased vertical movement
    
    // Create grid for sand particles
    vec2 gridPos = fract(uv * size);
    
    // Random position within cell
    vec2 cellPos = vec2(
        noise(floor(uv * size)),
        noise(floor(uv * size) + 1.0)
    );
    
    // Distance from grid position to cell position
    float dist = distance(gridPos, cellPos);
    
    // Create sand particle with soft edge
    return smoothstep(0.05, 0.0, dist);
}

void main() {
    // Sample map texture
    vec4 mapColor = texture2D(u_Tex0, v_TexCoord);
    
    // Animated time
    float time = u_Time * 0.3;
    
    // Create sand particles at different scales
    float sandSmall = sandParticle(v_WorldPos * 0.1, 8.0, time);
    float sandMedium = sandParticle(v_WorldPos * 0.05, 5.0, time * 0.8);
    
    // Combine sand particles
    float sandParticles = sandSmall * 0.3 + sandMedium * 0.2;
    
    // Create dust clouds
    vec2 dustCoord = v_WorldPos * 0.02;
    dustCoord.x += time * 0.5 * DIRECTION_X; // Move dust horizontally faster 
    dustCoord.y += time * 0.15; // Add slight downward drift
    
    float dust = fbm(dustCoord);
    
    // Create moving streaks of sand
    vec2 streakCoord = v_WorldPos * 0.08;
    streakCoord.x += time * 1.8 * DIRECTION_X; // Faster horizontal movement
    streakCoord.y += time * 0.4; // More noticeable downward drift
    float streaks = (noise(streakCoord) - 0.3) * 1.0;
    streaks = max(0.0, streaks);
    
    // Combine effects
    float sandFactor = sandParticles * 0.5 + dust * 0.3 + streaks * 0.4;
    sandFactor *= SAND_DENSITY;
    
    // Apply sandstorm visual effects
    vec4 finalColor = mapColor;
    
    // Desaturate scene slightly
    float luminance = dot(finalColor.rgb, vec3(0.299, 0.587, 0.114));
    finalColor.rgb = mix(finalColor.rgb, vec3(luminance), 0.2 * SAND_DENSITY);
    
    // Add sand particles
    finalColor.rgb = mix(finalColor.rgb, SAND_COLOR, sandParticles * 0.4 * SAND_DENSITY);
    
    // Add dust cloud
    finalColor.rgb = mix(finalColor.rgb, DUST_COLOR, dust * 0.3 * SAND_DENSITY);
    
    // Add sand streaks
    finalColor.rgb = mix(finalColor.rgb, SAND_COLOR, streaks * 0.2 * SAND_DENSITY);
    
    // Overall yellowish tint
    finalColor.rgb = mix(finalColor.rgb, DUST_COLOR, 0.1 * SAND_DENSITY);
    
    // Darken the scene slightly to simulate reduced visibility
    finalColor.rgb *= 1.0 - 0.1 * SAND_DENSITY;
    
    gl_FragColor = finalColor;
} 