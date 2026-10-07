uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Volcano ash parameters
const float ASH_SPEED = 0.4;           // Increased ash falling speed
const float ASH_DENSITY = 0.9;         // Increased amount of ash particles
const vec3 ASH_COLOR = vec3(0.08, 0.07, 0.07);  // Very dark ash color
const vec3 GLOW_COLOR = vec3(0.7, 0.2, 0.05); // Brighter reddish glow color
const float GLOW_STRENGTH = 0.25;      // Increased glow strength
const float DARKNESS = 0.3;            // Increased darkening of the scene
const float ASH_SIZE = 1.8;            // Increased size of ash particles

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

// Ash particle function
float ashParticle(vec2 uv, float time, float size, float speed) {
    // Move ash downward
    uv.y -= time * speed;
    
    // Add slight horizontal drift based on vertical position
    uv.x += sin(uv.y * 2.0 + time) * 0.2;
    
    // Create grid for ash particles
    vec2 gridPos = fract(uv * size);
    vec2 id = floor(uv * size);
    
    // Random position within cell
    vec2 cellPos = vec2(
        0.5 + 0.4 * sin(hash(id.x + id.y * 57.0) * 6.28),
        0.5 + 0.4 * sin(hash(id.y + id.x * 73.0) * 6.28)
    );
    
    // Random ash size (larger)
    float ashSize = 0.04 + 0.05 * hash(id.x * 33.3 + id.y * 77.7);
    ashSize *= ASH_SIZE; // Apply global size multiplier
    
    // Distance from grid position to cell position
    float dist = distance(gridPos, cellPos);
    
    // Create ash particle with soft edge
    return smoothstep(ashSize, ashSize - 0.02, dist);
}

// Glow effect based on position
float glowEffect(vec2 uv, float time) {
    // Create slow pulsating glow
    float glow = sin(time * 0.2) * 0.5 + 0.5;
    
    // Apply position-based variation
    glow *= noise2d(uv * 0.5 + time * 0.1);
    
    // Add secondary glow pattern
    glow += noise2d(uv * 0.3 - time * 0.05) * 0.3;
    
    return glow * GLOW_STRENGTH;
}

void main() {
    // Sample map texture
    vec4 mapColor = texture2D(u_Tex0, v_TexCoord);
    
    // Animated time
    float time = u_Time;
    
    // Generate ash particles at different scales and speeds
    float ash = 0.0;
    ash += ashParticle(v_WorldPos * 0.02, time, 8.0, ASH_SPEED);
    ash += ashParticle(v_WorldPos * 0.04, time * 0.8, 12.0, ASH_SPEED * 0.7) * 0.7;
    ash += ashParticle(v_WorldPos * 0.08, time * 1.2, 16.0, ASH_SPEED * 0.5) * 0.5;
    // Add fourth layer of smaller, faster particles
    ash += ashParticle(v_WorldPos * 0.15, time * 1.5, 24.0, ASH_SPEED * 0.9) * 0.3;
    
    ash = min(ash, 1.0) * ASH_DENSITY;
    
    // Calculate reddish glow
    float glow = glowEffect(v_WorldPos * 0.01, time);
    
    // Apply volcano ash effects to the scene
    vec4 finalColor = mapColor;
    
    // Darken the scene
    finalColor.rgb *= (1.0 - DARKNESS);
    
    // Add reddish glow
    finalColor.rgb = mix(finalColor.rgb, GLOW_COLOR, glow);
    
    // Add black ash particles
    finalColor.rgb = mix(finalColor.rgb, ASH_COLOR, ash * 0.7);
    
    // Add overall subtle red tint
    finalColor.rgb = mix(finalColor.rgb, GLOW_COLOR, 0.1);
    
    gl_FragColor = finalColor;
} 