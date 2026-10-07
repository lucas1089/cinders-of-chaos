uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Fog parameters
const float FOG_SPEED = 0.4;        // Doubled speed for more noticeable movement
const float FOG_DENSITY = 0.7;      // Increased thickness of fog
const float FOG_DETAIL = 1.3;       // Level of detail in fog
const vec3 FOG_COLOR = vec3(0.75, 0.76, 0.78); // Light grey fog
const float VISIBILITY_RADIUS = 100.0; // Size of the visibility circle around player
const float VISIBILITY_FALLOFF = 70.0; // How soft the edge of the visibility circle is

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
    float scale = 1.0;
    
    // Add several octaves of noise for more natural fog
    for(int i = 0; i < 5; i++) {
        val += amp * (snoise(pos * scale) * 0.5 + 0.5);
        amp *= 0.5;
        scale *= 2.0;
    }
    
    return val;
}

// Calculate visibility based on distance from center
float calculateVisibility(vec2 worldPos) {
    // Center is at (0,0) - this is where the player is
    float distFromCenter = length(worldPos);
    
    // Create a circular mask with smooth edges
    return smoothstep(VISIBILITY_RADIUS + VISIBILITY_FALLOFF, VISIBILITY_RADIUS, distFromCenter);
}

void main() {
    // Sample map texture
    vec4 mapColor = texture2D(u_Tex0, v_TexCoord);
    
    // Calculate fog with increased speed
    float time = u_Time * FOG_SPEED;
    
    // Create several layers of fog with different speeds and scales
    vec2 fogCoord1 = v_WorldPos * 0.01 * FOG_DETAIL;
    vec2 fogCoord2 = v_WorldPos * 0.02 * FOG_DETAIL;
    vec2 fogCoord3 = v_WorldPos * 0.005 * FOG_DETAIL;
    
    // Add stronger directional movement to fog - diagonal right
    fogCoord1 += vec2(time * 0.5, time * 0.3);  // Doubled movement speed
    
    // Add movement in opposite direction - diagonal left
    fogCoord2 += vec2(-time * 0.4, time * 0.2);  // Doubled movement speed
    
    // Add slow horizontal movement for third layer
    fogCoord3 += vec2(time * 0.3, -time * 0.1);  // Doubled movement speed
    
    // Generate fog using FBM noise
    float fog1 = fbm(fogCoord1);
    float fog2 = fbm(fogCoord2);
    float fog3 = fbm(fogCoord3);
    
    // Combine fog layers with different weights
    float fogFactor = (fog1 * 0.5 + fog2 * 0.3 + fog3 * 0.2) * FOG_DENSITY;
    
    // Calculate player-centered visibility
    float visibility = calculateVisibility(v_WorldPos);
    
    // Adjust fog density based on visibility (thicker fog farther from player)
    fogFactor *= mix(0.3, 1.0, visibility);
    
    // Apply fog to scene
    vec4 finalColor = mapColor;
    
    // Mix with fog color based on density
    finalColor.rgb = mix(finalColor.rgb, FOG_COLOR, fogFactor);
    
    // Add some depth by slightly darkening areas where fog is changing rapidly
    vec2 fogGrad = vec2(
        fbm(fogCoord1 + vec2(0.01, 0.0)) - fbm(fogCoord1 - vec2(0.01, 0.0)),
        fbm(fogCoord1 + vec2(0.0, 0.01)) - fbm(fogCoord1 - vec2(0.0, 0.01))
    );
    
    float fogEdges = length(fogGrad) * 2.0;
    finalColor.rgb *= 1.0 - fogEdges * 0.1;
    
    gl_FragColor = finalColor;
} 