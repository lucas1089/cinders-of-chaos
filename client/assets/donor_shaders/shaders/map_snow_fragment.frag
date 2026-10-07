uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Snow parameters
const int SNOW_LAYERS = 3;           // Number of snow layers
const float SPEED_FACTOR = 0.4;      // Overall snow speed
const float DENSITY_FACTOR = 0.8;    // Overall snow density
const float SOFT_LIGHT_INTENSITY = 0.15; // Intensity of soft lighting

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

// Snowflake function
float snowflake(vec2 uv, float scale, float time, float layer) {
    // Add layer variation
    float layerScale = scale * (1.0 - 0.2 * layer);
    float layerSpeed = SPEED_FACTOR * (1.0 + 0.5 * layer);
    
    // Snowflake positions
    vec2 pos = uv * layerScale;
    
    // Add falling movement
    pos.y += time * layerSpeed;
    
    // Add some horizontal drift
    pos.x += sin(pos.y * 0.1 + time * 0.2) * 0.2 * layer;
    
    // Generate snowflakes based on noise
    float snowNoise = noise2d(pos);
    
    // Threshold for snow visibility (layer-based density)
    float density = 0.65 + 0.1 * layer;
    
    // Make round snowflakes
    snowNoise = smoothstep(density, density + 0.05, snowNoise);
    
    // Reduce intensity based on layer
    return snowNoise * (1.0 - 0.3 * layer);
}

// Soft lighting effect function
vec3 addSoftLighting(vec3 color, vec2 worldPos, float time) {
    // Create soft light pattern
    vec2 lightPos = worldPos * 0.01;
    
    // Slowly animate light pattern
    lightPos.x += time * 0.05;
    lightPos.y += time * 0.03;
    
    // Generate soft light pattern using noise
    float lightPattern = 0.0;
    
    // Add multiple layers of noise for more interesting light pattern
    lightPattern += noise2d(lightPos) * 0.5;
    lightPattern += noise2d(lightPos * 2.0 + 0.5) * 0.3;
    lightPattern += noise2d(lightPos * 4.0 + 1.0) * 0.2;
    
    // Shape the light pattern
    lightPattern = smoothstep(0.3, 0.7, lightPattern);
    
    // Convert to soft white-blue light
    vec3 lightColor = mix(vec3(1.0), vec3(0.9, 0.95, 1.0), lightPattern);
    
    // Apply soft lighting overlay
    return mix(color, color * lightColor, lightPattern * SOFT_LIGHT_INTENSITY);
}

void main() {
    // Sample map texture
    vec4 mapColor = texture2D(u_Tex0, v_TexCoord);
    
    // Snow color (slightly blue-ish white)
    vec3 snowColor = vec3(0.9, 0.95, 1.0);
    
    // Initialize snow accumulation
    float snow = 0.0;
    
    // Generate multiple layers of snow with different scales and speeds
    for (int i = 0; i < SNOW_LAYERS; i++) {
        float scale = 20.0 + float(i) * 10.0;
        float layerTime = u_Time;
        snow += snowflake(v_WorldPos, scale, layerTime, float(i)) * (0.5 / float(SNOW_LAYERS));
    }
    
    // Apply snow to the scene
    vec4 finalColor = mapColor;
    finalColor.rgb = mix(finalColor.rgb, snowColor, snow * DENSITY_FACTOR);
    
    // Add a subtle blue tint to the entire scene for winter feel
    float winterTint = 0.03;
    finalColor.rgb = mix(finalColor.rgb, vec3(0.8, 0.9, 1.0), winterTint);
    
    // Add soft lighting overlay
    finalColor.rgb = addSoftLighting(finalColor.rgb, v_WorldPos, u_Time);
    
    gl_FragColor = finalColor;
}
