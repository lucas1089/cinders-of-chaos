uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform vec2 u_WalkingOffset;
uniform float u_Time;

// Vignette parameters
const float VIGNETTE_DARKNESS = 1.0;     // How dark the vignette gets (0-1)
const float VIGNETTE_SIZE = 0.75;         // Size of visible area (smaller = larger dark area)
const float VIGNETTE_SMOOTHNESS = 0.6;    // Edge softness (0 = hard, 1 = very soft)
const float VIGNETTE_SHARPNESS = 2.0;     // Edge sharpness via pow (higher = sharper falloff)

// Center offset - moves the vignette center
// Negative X = left, Positive X = right
// Negative Y = up, Positive Y = down
const vec2 CENTER_OFFSET = vec2(-0.035, 0.035);  // Move center to upper-left

// Bubble particle parameters
const vec3 PARTICLE_COLOR = vec3(0.65, 0.82, 1.0); // Color of bubble glints
const float PARTICLE_SCALE = 0.0015;         // Controls spacing of particles
const float PARTICLE_SCROLL = 0.2;          // Rising speed
const float PARTICLE_SWAY = 0.1;           // Horizontal drift
const float PARTICLE_FLICKER = 3.5;          // Flicker speed
const float BUBBLE_THRESHOLD = 0.75;         // Threshold for bubble visibility
const float BUBBLE_SOFTNESS = 0.55;          // Softness of bubble edges
const float BUBBLE_INTENSITY = 0.75;         // Strength of bubble glow

// Calculate vignette effect with walking offset compensation
float vignette(vec2 uv, vec2 walkingOffset, float size, float smoothness) {
    // Convert UV to -1 to 1 range (center at 0,0)
    uv = uv * 2.0 - 1.0;

    // Apply center offset to shift vignette position
    uv -= CENTER_OFFSET;

    // Apply walking offset for smooth centering during player movement
    // walkingOffset is the creature's current walk animation offset (normalized)
    // Goes from ~0.066 to 0 as player completes a step (32 pixels / ~480 map size)
    // This makes the vignette follow the player smoothly during walking
    uv -= walkingOffset * 2.0;

    // Calculate radial distance from center
    float radialDist = length(uv) / size;

    return smoothstep(1.0, 1.0 - smoothness, radialDist);
}

// Bubble particles effect
float bubbleParticles(vec2 worldPos, float time) {
    // Base UV derived from world position to keep particles anchored in space
    vec2 uv = worldPos * PARTICLE_SCALE;

    // Slow upward motion to mimic bubbles rising
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

    // Calculate vignette with walking offset compensation for smooth centering
    float vig = vignette(v_TexCoord, u_WalkingOffset, VIGNETTE_SIZE, VIGNETTE_SMOOTHNESS);
    vig = pow(vig, VIGNETTE_SHARPNESS); // Sharpen vignette edge

    // Calculate bubble particle effect
    float particleGlow = bubbleParticles(v_WorldPos, u_Time) * BUBBLE_INTENSITY;

    // Apply bubble glow with subtle additive tint
    color.rgb = mix(color.rgb, color.rgb + PARTICLE_COLOR * 0.8, particleGlow);

    // Apply vignette (strong shadows on edges, clear in center)
    color.rgb *= mix(1.0 - VIGNETTE_DARKNESS, 1.0, vig);

    gl_FragColor = color;
}
