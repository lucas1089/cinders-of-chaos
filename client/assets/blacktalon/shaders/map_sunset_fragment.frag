uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Sunset parameters
const vec3 SUNSET_COLOR = vec3(0.95, 0.5, 0.2);   // Orange-red sunset color
const vec3 SKY_COLOR = vec3(0.4, 0.3, 0.7);       // Purple-blue sky color
const float TINT_STRENGTH = 0.4;                  // Overall sunset coloring strength
const float SHADOW_STRENGTH = 0.35;               // Darkness of sunset shadows
const float SUN_POSITION = 0.8;                   // Position factor of sun (0-1)
const float SUN_GLOW_SIZE = 0.4;                  // Size of sun glow

// Calculate sunset color based on position
vec3 getSunsetColor(vec2 pos, float time) {
    // Slow sun movement
    float sunMovement = sin(time * 0.05) * 0.1;
    
    // Horizontal position affects sunset color (redder near the edge)
    float horizonFactor = smoothstep(0.0, 1.0, pos.x);
    
    // Create sunset gradient
    vec3 color = mix(SUNSET_COLOR, SKY_COLOR, horizonFactor);
    
    // Add sun glow
    float sunX = SUN_POSITION + sunMovement;
    float sunY = 0.4 + sin(time * 0.1) * 0.05;
    float distToSun = distance(pos, vec2(sunX, sunY));
    
    // Sun glow
    float sunGlow = smoothstep(SUN_GLOW_SIZE, 0.0, distToSun);
    color = mix(color, vec3(1.0, 0.9, 0.7), sunGlow * 0.6);
    
    return color;
}

// Calculate shadow based on world position
float getShadow(vec2 pos, float time) {
    // Shadow angle varies slowly with time
    float shadowAngle = 1.0 + sin(time * 0.05) * 0.2;
    
    // Create diagonal shadow lines
    float shadowVal = sin(pos.x * shadowAngle + pos.y * 5.0 + time * 0.1);
    shadowVal = smoothstep(0.0, 0.8, shadowVal);
    
    // Vertical position affects shadow intensity (stronger at bottom)
    float verticalFade = smoothstep(0.0, 0.8, pos.y);
    shadowVal *= verticalFade;
    
    return shadowVal;
}

void main() {
    // Animated time
    float time = u_Time * 0.5;
    
    // Sample map texture
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    
    // Normalized coordinates for sunset effect
    vec2 normalizedPos = v_WorldPos * 0.01;
    
    // Get sunset color for this position
    vec3 sunsetColor = getSunsetColor(normalizedPos, time);
    
    // Apply sunset tint to scene
    color.rgb = mix(color.rgb, color.rgb * sunsetColor, TINT_STRENGTH);
    
    // Add warm highlight to bright areas
    float brightness = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, color.rgb * vec3(1.1, 0.9, 0.7), brightness * 0.3);
    
    // Calculate shadows
    float shadow = getShadow(normalizedPos, time);
    
    // Apply shadows
    color.rgb *= 1.0 - (shadow * SHADOW_STRENGTH);
    
    // Add subtle violet tint to shadows
    color.rgb = mix(color.rgb, color.rgb * vec3(0.7, 0.5, 0.9), shadow * 0.1);
    
    // Overall warming
    color.rgb = mix(color.rgb, color.rgb * vec3(1.1, 0.9, 0.8), 0.2);
    
    // Increase contrast slightly
    color.rgb = mix(vec3(0.5), color.rgb, 1.1);
    
    gl_FragColor = color;
} 