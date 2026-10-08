uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Toxic fog parameters
const float FOG_SPEED = 0.3;                // Speed of fog movement
const float FOG_DENSITY = 0.2;              // Further reduced density for better visibility (was 0.25)
const vec3 FOG_COLOR = vec3(0.2, 0.7, 0.1); // Toxic green
const vec3 FOG_COLOR2 = vec3(0.1, 0.5, 0.0); // Darker green for variation
const float EDGE_BLUR = 0.1;                // Further reduced edge blur (was 0.15)
const float BLUR_ITERATIONS = 2.0;          // Minimal blur samples (was 3.0)
const float BUBBLE_SCALE = 3.0;             // Scale of bubble effect
const float BUBBLE_SPEED = 0.2;             // Speed of bubble movement
const float VISIBILITY_CENTER = 0.7;        // Even more visibility in center (was 0.6)
const float BLIND_SPOT_SIZE = 0.15;         // Size of clear areas in fog
const float BLIND_SPOT_CLARITY = 0.8;       // How clear the blind spots are (0-1)

// Simplex noise functions
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

// FBM (Fractal Brownian Motion) for layered fog
float fbm(vec2 pos) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    
    // Add several octaves of noise for more natural fog
    for(int i = 0; i < 5; i++) {
        val += amp * (snoise(pos * freq) * 0.5 + 0.5);
        amp *= 0.5;
        freq *= 2.0;
    }
    
    return val;
}

// Edge blur effect
vec4 edgeBlur(sampler2D tex, vec2 uv, float strength) {
    // If blur strength is very low, just return the texture directly
    if (strength < 0.05) return texture2D(tex, uv);
    
    vec4 color = vec4(0.0);
    float total = 0.0;
    float offset = strength / 50.0; // Further reduced offset (was /40.0)
    
    // Simple gaussian blur with minimal iterations
    for(float x = -BLUR_ITERATIONS; x <= BLUR_ITERATIONS; x += 1.0) {
        for(float y = -BLUR_ITERATIONS; y <= BLUR_ITERATIONS; y += 1.0) {
            vec2 sampleUV = uv + vec2(x, y) * offset;
            float weight = (BLUR_ITERATIONS - abs(x)) * (BLUR_ITERATIONS - abs(y));
            color += texture2D(tex, sampleUV) * weight;
            total += weight;
        }
    }
    
    return color / total;
}

// Create toxic bubble effect
float toxicBubbles(vec2 pos, float time) {
    // Create different sized bubbles
    float bubbles = 0.0;
    
    // Small fast bubbles
    vec2 bubblePos1 = pos * 0.05 * BUBBLE_SCALE;
    bubblePos1.y += time * BUBBLE_SPEED * 1.5;
    float bubble1 = snoise(bubblePos1) * 0.5 + 0.5;
    bubble1 = smoothstep(0.4, 0.6, bubble1);
    
    // Medium bubbles
    vec2 bubblePos2 = pos * 0.02 * BUBBLE_SCALE;
    bubblePos2.y += time * BUBBLE_SPEED;
    float bubble2 = snoise(bubblePos2) * 0.5 + 0.5;
    bubble2 = smoothstep(0.3, 0.7, bubble2);
    
    // Combine bubbles
    bubbles = bubble1 * 0.3 + bubble2 * 0.7;
    
    return bubbles * 0.1; // Further reduced intensity (was 0.12)
}

// Calculate visibility mask (more visible in center around player position)
float visibilityMask(vec2 worldPos) {
    float distFromCenter = length(worldPos) * 0.003; // Further reduced factor for wider clear area
    return max(0.0, min(1.0, VISIBILITY_CENTER + distFromCenter));
}

// Create blind spots in the fog for better visibility
float blindSpots(vec2 worldPos, float time) {
    // Create a pattern of clear areas using simplex noise
    vec2 spotPos = worldPos * 0.005;
    spotPos.x += time * 0.02; // Very slow movement
    
    // Create several noise patterns at different scales
    float bigSpots = smoothstep(0.6, 0.7, snoise(spotPos) * 0.5 + 0.5);
    float smallSpots = smoothstep(0.65, 0.75, snoise(spotPos * 2.0) * 0.5 + 0.5);
    
    // Combine different sized spots for more organic clear areas
    float spots = max(bigSpots, smallSpots) * BLIND_SPOT_CLARITY;
    
    return spots;
}

void main() {
    // Calculate animated time
    float time = u_Time * FOG_SPEED;
    
    // Sample original texture with minimal edge blur
    vec4 color = edgeBlur(u_Tex0, v_TexCoord, EDGE_BLUR);
    
    // Generate fog layers at different scales/speeds
    vec2 fogPos1 = v_WorldPos * 0.01;
    fogPos1 += vec2(time * 0.5, time * 0.3);
    float fog1 = fbm(fogPos1);
    
    vec2 fogPos2 = v_WorldPos * 0.02;
    fogPos2 += vec2(-time * 0.4, time * 0.5);
    float fog2 = fbm(fogPos2);
    
    // Combine fog layers
    float fogFactor = fog1 * 0.6 + fog2 * 0.4;
    
    // Add visibility mask - less fog in the center
    float visibility = visibilityMask(v_WorldPos);
    
    // Add blind spots for better visibility through the fog
    float spots = blindSpots(v_WorldPos, u_Time);
    
    // Combine visibility mask and blind spots
    fogFactor *= FOG_DENSITY * max(visibility - spots, 0.0);
    
    // Create bubble effect
    float bubbles = toxicBubbles(v_WorldPos, u_Time);
    
    // Create pulsating glow for extra toxic effect
    float pulse = sin(u_Time * 0.3) * 0.5 + 0.5;
    pulse *= 0.1; // Further reduced glow intensity (was 0.12)
    
    // Apply fog and effects with more original color preserved
    vec3 fogColor = mix(FOG_COLOR, FOG_COLOR2, fog2);
    color.rgb = mix(color.rgb, fogColor, fogFactor);
    
    // Add bubbles with reduced effect
    color.rgb = mix(color.rgb, FOG_COLOR * 1.5, bubbles);
    
    // Add pulse
    color.rgb += fogColor * pulse;
    
    // Add vignette with less darkness at the edges
    vec2 uv = v_TexCoord * 2.0 - 1.0;
    float vignette = 1.0 - dot(uv, uv) * 0.2; // Reduced from 0.25
    color.rgb *= vignette;
    
    gl_FragColor = color;
} 