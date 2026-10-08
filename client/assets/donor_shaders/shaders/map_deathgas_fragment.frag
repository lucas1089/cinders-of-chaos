uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Death Gas Wave Parameters
const float WAVE_SPEED = 20.0;          // Speed at which gas front advances (pixels per second)
const float PARTICLE_START_TIME = 18.0; // When particles start appearing
const float TOXIC_BASE_COLOR = 0.8;     // Base intensity of toxic color
const float ROOM_HEIGHT = 1000.0;       // Approximate height of room for wave calculation
const float MAX_OPACITY = 0.7;          // Maximum opacity for the gas effect (70%)
const float LAYER_THICKNESS = 100.0;    // Thickness of each gas layer
const float LAYER_COUNT = 5.0;          // Number of visible layers behind the front

// Death Gas parameters
const vec3 GAS_COLOR1 = vec3(0.3, 1.0, 0.2);   // Bright toxic green
const vec3 GAS_COLOR2 = vec3(0.2, 0.7, 0.1);   // Medium toxic green
const vec3 GAS_COLOR3 = vec3(0.5, 1.0, 0.0);   // Yellow-green
const vec3 PARTICLE_COLOR = vec3(0.7, 1.0, 0.3); // Glowing particle color

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

// Gas particle function
float gasParticle(vec2 uv, float time, float size, float speed, float particleSize) {
    // Move particles with the advancing front
    uv.y -= time * speed;
    uv.x += sin(time * 1.5) * 0.2;
    
    // Create grid for gas particles
    vec2 gridPos = fract(uv * size);
    vec2 id = floor(uv * size);
    
    // Random position within cell
    vec2 cellPos = vec2(
        0.5 + 0.4 * sin(hash(id.x + id.y * 57.0) * 6.28),
        0.5 + 0.4 * sin(hash(id.y + id.x * 73.0) * 6.28)
    );
    
    // Distance from grid position to cell position
    float dist = distance(gridPos, cellPos);
    
    // Create gas particle with soft edge
    return smoothstep(particleSize, particleSize - 0.01, dist);
}

// Gas gradient with layer effect
vec3 gasGradient(float value, float layer) {
    // Create a gas gradient based on value
    vec3 color = mix(GAS_COLOR2, GAS_COLOR1, value);
    color = mix(color, GAS_COLOR3, max(0.0, value - 0.7) * 3.0);
    
    // Adjust color slightly based on layer for visual variety
    float layerAdjust = sin(layer * 3.14159 * 2.0) * 0.1;
    color += vec3(layerAdjust * 0.1, layerAdjust * 0.2, 0.0);
    
    return color;
}

void main() {
    // Calculate time and position variables
    float time = u_Time;
    
    // Calculate the advancing front position (moves up continuously)
    float frontPosition = WAVE_SPEED * time;
    
    // Sample original texture with heat distortion
    vec2 distortedUV = v_TexCoord;
    float heat = sin(v_WorldPos.y * 0.01 + time * 2.0) * cos(v_WorldPos.x * 0.01 + time) * 0.002;
    heat *= 0.4; // Basic heat distortion
    distortedUV.x += heat;
    
    vec4 color = texture2D(u_Tex0, distortedUV);
    
    // Calculate normalized Y position (0 at bottom, 1 at top)
    float normalizedY = v_WorldPos.y;
    
    // Calculate distance from advancing front
    float distanceFromFront = frontPosition - normalizedY;
    
    // Determine if point is within the gas (behind the front)
    float inGas = smoothstep(-20.0, 0.0, distanceFromFront);
    
    // Calculate the layer based on distance from front
    float layer = floor(distanceFromFront / LAYER_THICKNESS);
    layer = clamp(layer, 0.0, LAYER_COUNT - 1.0);
    float layerProgress = fract(distanceFromFront / LAYER_THICKNESS);
    
    // Calculate layer opacity
    float layerOpacity = (LAYER_COUNT - layer) / LAYER_COUNT;
    layerOpacity = max(layerOpacity, 0.3); // Ensure even distant layers have some presence
    
    // Create front edge glow effect
    float frontGlow = smoothstep(20.0, 0.0, abs(distanceFromFront)) * 2.0;
    
    // Check if in the dead zone (far behind the front)
    float inDeadZone = smoothstep(LAYER_THICKNESS * 2.0, LAYER_THICKNESS * 3.0, distanceFromFront);
    
    // Generate gas patterns
    vec2 gasPos = v_WorldPos * 0.01;
    gasPos.y += time * 0.3;
    gasPos.x += sin(gasPos.y * 4.0) * 0.1;
    
    float gasNoise = fbm(gasPos * 2.0);
    
    // Add smaller details to gas
    float gasDetails = fbm(gasPos * 5.0 + time * 0.5) * 0.5;
    
    // Combine gas effects
    float finalGasEffect = (gasNoise * 0.7 + gasDetails * 0.3) * inGas;
    
    // Add layer variation to gas
    finalGasEffect *= (0.7 + sin(layer + layerProgress * 3.14159) * 0.3);
    
    // Particle effects that start appearing after PARTICLE_START_TIME
    float particleEffect = 0.0;
    if (time > PARTICLE_START_TIME) {
        float particleTime = time - PARTICLE_START_TIME;
        float particleIntensity = min(particleTime / 20.0, 1.0); // Gradually increase over 20 seconds
        
        for (int i = 0; i < 3; i++) { // Three layers of particles
            float speed = 0.1 + float(i) * 0.05;
            float size = 15.0 + float(i) * 5.0;
            float particleSize = 0.02 + 0.01 * particleIntensity;
            
            particleEffect += gasParticle(v_WorldPos * 0.02, time, size, speed, particleSize) * 
                               (0.3 - float(i) * 0.05) * particleIntensity;
        }
        
        // Limit particle effect
        particleEffect = min(particleEffect, 1.0) * inGas;
    }
    
    // Calculate particle glow factor based on time
    float particleGlow = 0.0;
    if (time > PARTICLE_START_TIME + 10.0) { // Start glowing 10 seconds after particles appear
        particleGlow = min((time - (PARTICLE_START_TIME + 10.0)) / 15.0, 1.0); // Increase over 15 seconds
    }
    
    // Apply gas tint and effects to the scene
    vec3 gasTint = gasGradient(finalGasEffect, layer);
    
    // Add dead zone effect (more opaque, more toxic)
    float opacity = MAX_OPACITY * layerOpacity;
    if (inDeadZone > 0.0) {
        // Make the dead zone more toxic looking
        gasTint = mix(gasTint, GAS_COLOR3 * 1.2, inDeadZone * 0.3);
        opacity = mix(opacity, MAX_OPACITY, inDeadZone);
    }
    
    // Apply the gas color with opacity
    color.rgb = mix(color.rgb, gasTint, finalGasEffect * opacity);
    
    // Add gas glow
    color.rgb += gasTint * finalGasEffect * 0.3 * layerOpacity;
    
    // Add front edge glow
    color.rgb += GAS_COLOR1 * frontGlow * 0.3;
    
    // Add particles
    color.rgb = mix(color.rgb, PARTICLE_COLOR, particleEffect * 0.6);
    
    // Add particle glow
    color.rgb += PARTICLE_COLOR * particleEffect * particleGlow * 0.5;
    
    // Add pulsating gas intensity
    float pulse = sin(time * 1.0) * 0.5 + 0.5;
    color.rgb += gasTint * pulse * 0.05 * inGas;
    
    gl_FragColor = color;
} 