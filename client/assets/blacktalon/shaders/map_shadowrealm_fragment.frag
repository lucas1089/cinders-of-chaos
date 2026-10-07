uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;
uniform vec2 u_LocalPlayerScreenPos; // Player position on screen (normalized 0-1)

// Shadow realm parameters
const float GRAYSCALE_STRENGTH = 0.0;      // How much to desaturate (0-1)
const float INVERT_STRENGTH = 0.1;         // How much to invert colors (0-1)
const float VIGNETTE_DARKNESS = 0.93;      // How dark the vignette gets
const float VIGNETTE_SIZE = 0.75;           // Size of vignette (smaller = larger effect)
const float SHADOW_WAVER = 0.75;             // Strength of particle glow
const vec3 SHADOW_COLOR = vec3(0.05, 0.0, 0.1); // Dark purple shadow color
const vec3 PARTICLE_COLOR = vec3(0.65, 0.82, 1.0); // Color of bubble glints
const float PARTICLE_SCALE = 0.0015;         // Controls spacing of particles
const float PARTICLE_SCROLL = 0.2;          // Rising speed
const float PARTICLE_SWAY = 0.1;           // Horizontal drift
const float PARTICLE_FLICKER = 3.5;          // Flicker speed
const float BUBBLE_THRESHOLD = 0.75;         // Threshold for bubble visibility
const float BUBBLE_SOFTNESS = 0.55;          // Softness of bubble edges

// Calculate vignette effect
float vignette(vec2 uv, float size, float smoothness) {
    uv = uv * 2.0 - 1.0;
    float radialDist = length(uv) / size;
    return smoothstep(1.0, 1.0 - smoothness, radialDist);
}

float snowParticles(vec2 worldPos, float time) {
    // Base UV derived from world position to keep particles anchored in space
    vec2 uv = worldPos * PARTICLE_SCALE;
    
    // Slow upward motion to mimic particles rising in water
    uv.y += time * PARTICLE_SCROLL;
    
    // Gentle sway influenced by world position for variation
    uv.x += sin(worldPos.y * 0.01 + time * 0.25) * PARTICLE_SWAY;
    
    // Wrap coordinates to sample within the texture atlas
    uv = fract(uv);
    
    // Sample bubble texture channels for shape and detail
    vec3 baseSample = texture2D(u_Tex1, uv).rgb;
    vec3 detailSample = texture2D(u_Tex1, fract(uv * 1.2 + vec2(time * 0.04, -time * 0.02))).rgb;
    
    float luminance = dot(baseSample, vec3(0.299, 0.587, 0.114));
    float particleMask = smoothstep(BUBBLE_THRESHOLD, BUBBLE_THRESHOLD + BUBBLE_SOFTNESS, luminance);
    
    float detailLum = dot(detailSample, vec3(0.299, 0.587, 0.114));
    float flicker = smoothstep(0.25, 0.75, sin(time * PARTICLE_FLICKER + detailLum * 6.283) * 0.5 + 0.5);
    
    return particleMask * flicker;
}

void main() {
    // Sample original texture
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    
    // Calculate strong vignette
    float vig = vignette(v_TexCoord, VIGNETTE_SIZE, 0.6);
    vig = pow(vig, 2.0); // Sharpen vignette edge
    
    // Floating particle effect sampled from snow texture
    float particleGlow = snowParticles(v_WorldPos, u_Time) * SHADOW_WAVER;
    
    // Convert to grayscale
    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    vec3 grayscale = vec3(luminance);
    
    // Apply partial color inversion
    vec3 inverted = 1.0 - color.rgb;
    
    // Mix the inverted and grayscale effects
    vec3 colorEffect = mix(grayscale, inverted, INVERT_STRENGTH);
    
    // Apply shadow color to dark areas
    colorEffect = mix(colorEffect, SHADOW_COLOR, (1.0 - luminance) * 0.6);
    
    // Apply color effects
    color.rgb = mix(color.rgb, colorEffect, GRAYSCALE_STRENGTH);
    
    // Apply particle glow with subtle additive tint
    color.rgb = mix(color.rgb, color.rgb + PARTICLE_COLOR * 0.8, particleGlow);
    
    // Apply vignette (strong shadows on edges)
    color.rgb *= mix(1.0 - VIGNETTE_DARKNESS, 1.0, vig);
    
    // Overall darkening
    color.rgb *= 0.7;
    
    // Add subtle purple tint to shadows
    color.rgb = mix(color.rgb, SHADOW_COLOR, (1.0 - luminance) * 0.3);
    
    gl_FragColor = color;
} 
