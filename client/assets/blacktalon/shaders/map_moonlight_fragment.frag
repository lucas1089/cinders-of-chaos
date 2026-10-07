uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Moonlight parameters
const vec3 MOONLIGHT_COLOR = vec3(0.2, 0.3, 0.6);  // Deep blue tint
const vec3 GLOW_COLOR = vec3(0.4, 0.6, 0.9);       // Cold blue glow
const float GLOW_STRENGTH = 0.4;                   // Ambient glow intensity
const float DARKNESS = 0.5;                        // Overall darkness
const float MOONLIGHT_PULSE = 0.1;                 // Subtle pulse for moonlight
const float MOVEMENT_SPEED = 0.15;                 // Speed of moonlight movement (increased)

// Simplex noise function for organic patterns
vec3 permute(vec3 x) { return mod(((x*34.0)+1.0)*x, 289.0); }

float snoise(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
            -0.577350269189626, 0.024390243902439);
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1;
    i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod(i, 289.0);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m*m;
    m = m*m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

// Create ambient glow patterns
float ambientGlow(vec2 position, float time) {
    // Movement direction vectors (positive x for left, positive y for bottom)
    vec2 direction1 = vec2(MOVEMENT_SPEED, MOVEMENT_SPEED * 0.7);
    vec2 direction2 = vec2(MOVEMENT_SPEED * 1.2, MOVEMENT_SPEED * 0.5);
    
    // Create large-scale soft noise pattern for ambient glow with directional movement
    float noise1 = snoise(position * 0.01 + time * direction1) * 0.5 + 0.5;
    float noise2 = snoise(position * 0.02 + time * direction2) * 0.5 + 0.5;
    
    // Combine noise layers for more organic look
    float pattern = noise1 * 0.7 + noise2 * 0.3;
    
    // Add time-based pulsing to the glow
    float pulse = sin(time * 0.2) * MOONLIGHT_PULSE + (1.0 - MOONLIGHT_PULSE);
    
    return pattern * pulse;
}

// Create a vignette effect
float vignette(vec2 uv, float intensity) {
    uv = uv * 2.0 - 1.0;
    return 1.0 - dot(uv, uv) * intensity;
}

void main() {
    // Sample the original texture
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    
    // Calculate ambient glow effect with movement
    float glow = ambientGlow(v_WorldPos, u_Time);
    
    // Create soft vignette
    float vignetteEffect = vignette(v_TexCoord, 0.4);
    
    // Create a focused moonlight effect - stronger in the center
    // Also move the center position over time for a moving light effect
    vec2 centerOffset = vec2(sin(u_Time * MOVEMENT_SPEED) * 100.0, cos(u_Time * MOVEMENT_SPEED * 0.7) * 80.0);
    float centerDistance = length(v_WorldPos + centerOffset) * 0.005;
    float focusedGlow = max(0.0, 1.0 - centerDistance) * 0.3;
    
    // Combine glow effects
    float combinedGlow = glow * 0.7 + focusedGlow * 0.3;
    
    // Apply darkness
    color.rgb *= (1.0 - DARKNESS);
    
    // Apply deep blue moonlight tint
    color.rgb = mix(color.rgb, MOONLIGHT_COLOR, 0.6);
    
    // Apply cold ambient glow
    color.rgb = mix(color.rgb, GLOW_COLOR, combinedGlow * GLOW_STRENGTH);
    
    // Apply vignette
    color.rgb *= vignetteEffect;
    
    // Slightly desaturate the image for night effect
    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, vec3(luminance), 0.2);
    
    gl_FragColor = color;
} 