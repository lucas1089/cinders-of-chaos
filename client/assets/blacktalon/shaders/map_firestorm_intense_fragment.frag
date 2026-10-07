uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Intense Firestorm parameters
const float FIRE_INTENSITY = 1.0;              // Increased intensity of fire effect
const float ASH_DENSITY = 0.8;                 // Increased density of ash particles
const float HEAT_DISTORTION = 0.7;             // Increased amount of heat distortion
const vec3 FIRE_COLOR1 = vec3(1.0, 0.6, 0.1);  // Bright orange
const vec3 FIRE_COLOR2 = vec3(1.0, 0.1, 0.0);  // Intense red
const vec3 FIRE_COLOR3 = vec3(1.0, 0.9, 0.3);  // Bright yellow
const float GLOW_STRENGTH = 0.7;               // Increased strength of the fiery glow
const float WIND_SPEED = 0.6;                  // Increased speed of wind/fire movement

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

// Fractal Brownian Motion
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    // Add octaves of noise
    for(int i = 0; i < 5; i++) {
        value += amplitude * noise2d(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// Ash particle function
float ashParticle(vec2 uv, float time, float size, float speed) {
    // Move ash upward (fire makes ash rise) and to the side (wind)
    uv.y -= time * speed;
    uv.x -= time * speed * 0.3; // Wind carrying the ash
    
    // Create grid for ash particles
    vec2 gridPos = fract(uv * size);
    vec2 id = floor(uv * size);
    
    // Random position within cell
    vec2 cellPos = vec2(
        0.5 + 0.4 * sin(hash(id.x + id.y * 57.0) * 6.28),
        0.5 + 0.4 * sin(hash(id.y + id.x * 73.0) * 6.28)
    );
    
    // Random ash size
    float ashSize = 0.03 + 0.05 * hash(id.x * 33.3 + id.y * 77.7);
    
    // Distance from grid position to cell position
    float dist = distance(gridPos, cellPos);
    
    // Create ash particle with soft edge
    return smoothstep(ashSize, ashSize - 0.01, dist);
}

// Fire gradient
vec3 fireGradient(float value) {
    // Create a fire gradient based on value
    vec3 color = mix(FIRE_COLOR2, FIRE_COLOR1, value);
    color = mix(color, FIRE_COLOR3, max(0.0, value - 0.6) * 2.5);
    
    return color;
}

void main() {
    // Animated time
    float time = u_Time * WIND_SPEED;
    
    // Sample original texture with heat distortion
    vec2 distortedUV = v_TexCoord;
    float heat = sin(v_WorldPos.y * 0.01 + time * 2.0) * cos(v_WorldPos.x * 0.01 + time) * 0.004;
    heat *= HEAT_DISTORTION;
    distortedUV.x += heat;
    
    vec4 color = texture2D(u_Tex0, distortedUV);
    
    // Generate fire noise pattern
    vec2 firePos = v_WorldPos * 0.008; // Reduced scaling for wider reach
    firePos.y -= time * 1.8; // Fire moves upward faster
    firePos.x += sin(firePos.y * 5.0) * 0.15; // More swirling flames
    
    float fireNoise = fbm(firePos * 2.0);
    
    // Make fire more intense at the bottom with wider vertical gradient
    float verticalGradient = smoothstep(0.0, 1.0, 1.0 - v_WorldPos.y * 0.0007); // Reduced scaling for longer range
    fireNoise *= verticalGradient;
    
    // Add smaller details to fire
    float fireDetails = fbm(firePos * 6.0 + time * 0.6) * 0.6;
    
    // Combine fire effects
    float fireEffect = fireNoise * 0.7 + fireDetails * 0.3;
    fireEffect = smoothstep(0.25, 0.7, fireEffect) * FIRE_INTENSITY; // Wider smoothstep range
    
    // Generate ash particles at different scales and speeds
    float ash = 0.0;
    ash += ashParticle(v_WorldPos * 0.025, time, 12.0, 0.3) * 0.5;
    ash += ashParticle(v_WorldPos * 0.04, time * 0.8, 18.0, 0.4) * 0.3;
    ash += ashParticle(v_WorldPos * 0.07, time * 0.6, 25.0, 0.5) * 0.2;
    ash = min(ash, 1.0) * ASH_DENSITY;
    
    // Apply fire tint to the scene
    vec3 fireTint = fireGradient(fireEffect);
    color.rgb = mix(color.rgb, fireTint, fireEffect * 0.7);
    
    // Add fire glow
    color.rgb += fireTint * fireEffect * GLOW_STRENGTH;
    
    // Add ash particles (dark red/black)
    color.rgb = mix(color.rgb, vec3(0.25, 0.05, 0.0), ash * 0.3);
    
    // Make the scene darker overall to emphasize the fire
    color.rgb *= 0.7;
    
    // Add pulsating glow
    float pulse = sin(time * 3.0) * 0.5 + 0.5;
    color.rgb += fireTint * pulse * 0.15;
    
    gl_FragColor = color;
} 