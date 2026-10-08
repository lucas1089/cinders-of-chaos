uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Cloudy parameters
const float CLOUD_SPEED = 2.0;         // Increased speed for noticeable movement
const float CLOUD_DENSITY = 0.7;       // Increased cloud thickness
const float BRIGHTNESS_REDUCTION = 0.2; // Overall darkening
const vec3 CLOUD_COLOR = vec3(0.8, 0.8, 0.85); // Soft gray-white clouds

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

// FBM (Fractal Brownian Motion) for cloud layers
float fbm(vec2 pos) {
    float val = 0.0;
    float amp = 0.5;
    float scale = 1.0;
    
    // Add several octaves of noise for fluffy clouds
    for(int i = 0; i < 5; i++) {
        val += amp * (snoise(pos * scale) * 0.5 + 0.5);
        amp *= 0.5;
        scale *= 2.0;
    }
    
    return val;
}

// Function to create cloud shapes
float cloudShape(vec2 uv, float time) {
    // Create multiple cloud layers with more pronounced movement
    float clouds = 0.0;
    
    // First cloud layer - large, slow-moving
    vec2 cloudCoord1 = uv * 0.2;
    cloudCoord1.x += time * 0.15;  // Increased speed for visibility
    cloudCoord1.y += time * 0.05;
    float cloud1 = fbm(cloudCoord1);
    
    // Second cloud layer - medium, different direction
    vec2 cloudCoord2 = uv * 0.4;
    cloudCoord2.x -= time * 0.1;
    cloudCoord2.y += time * 0.075;
    float cloud2 = fbm(cloudCoord2);
    
    // Third cloud layer - smaller details
    vec2 cloudCoord3 = uv * 0.8;
    cloudCoord3.x += time * 0.2;
    cloudCoord3.y -= time * 0.1;
    float cloud3 = fbm(cloudCoord3);
    
    // Fourth cloud layer - tiny details for more variation
    vec2 cloudCoord4 = uv * 1.6;
    cloudCoord4.x -= time * 0.25;
    cloudCoord4.y -= time * 0.15;
    float cloud4 = fbm(cloudCoord4);
    
    // Combine clouds with different weights
    clouds = cloud1 * 0.5 + cloud2 * 0.3 + cloud3 * 0.15 + cloud4 * 0.05;
    
    // Shape the clouds - make some areas more defined
    clouds = smoothstep(0.35, 0.65, clouds);
    
    return clouds;
}

void main() {
    // Sample map texture
    vec4 mapColor = texture2D(u_Tex0, v_TexCoord);
    
    // Calculate animated time for clouds
    float time = u_Time * CLOUD_SPEED;
    
    // Generate cloud pattern with current time
    float clouds = cloudShape(v_WorldPos * 0.01, time);
    
    // Adjust cloud density
    clouds *= CLOUD_DENSITY;
    
    // Apply clouds to the scene
    vec4 finalColor = mapColor;
    
    // Reduce overall brightness
    finalColor.rgb *= (1.0 - BRIGHTNESS_REDUCTION);
    
    // Add soft cloud overlay
    finalColor.rgb = mix(finalColor.rgb, CLOUD_COLOR, clouds * 0.5);
    
    // No shadows - reduce contrast
    float luminance = dot(finalColor.rgb, vec3(0.299, 0.587, 0.114));
    finalColor.rgb = mix(finalColor.rgb, vec3(luminance) * CLOUD_COLOR, 0.2);
    
    gl_FragColor = finalColor;
} 