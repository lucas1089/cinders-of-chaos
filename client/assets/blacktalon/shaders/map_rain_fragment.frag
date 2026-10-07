uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Rain parameters
const float RAIN_SPEED = 0.3;       // Very slow rain speed
const float RAIN_DENSITY = 0.7;     // How much rain
const float RIPPLE_SPEED = 0.3;     // How fast ripples form and fade
const float DARKNESS = 0.15;        // Darkness added by the rain
const float DESATURATION = 0.15;    // How much to desaturate the colors

// Hash function
float hash(vec2 p) {
    p = 50.0 * fract(p * 0.3183099);
    return fract(p.x * p.y * (p.x + p.y));
}

// Noise function
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    return mix(
        mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

// Rain line function
float rainLine(vec2 uv, float time) {
    // Rain streak parameters
    vec2 aspect = vec2(1.0, 5.0);  // Streaks are 5x taller than wide
    float speed = time * RAIN_SPEED;
    
    // Calculate the grid for rain drops
    vec2 st = uv * aspect;
    
    // Offset each column of rain to make it look more natural
    float columnOffset = noise(vec2(floor(st.x), 0.0)) * 0.8;
    
    // Create rain drops
    vec2 pos = vec2(
        fract(st.x),
        fract(st.y + speed + columnOffset)
    );
    
    // Draw the rain streak as a smooth line
    float rainDrop = smoothstep(0.0, 0.1, pos.y) * smoothstep(1.0, 0.8, pos.y);
    
    // Make some rain drops thinner than others
    float thickness = mix(0.03, 0.06, noise(st * 2.0));
    rainDrop *= smoothstep(thickness, 0.0, abs(pos.x - 0.5));
    
    return rainDrop;
}

// Ripple function - for rain hitting the ground
float ripple(vec2 uv, float time) {
    float t = time * RIPPLE_SPEED;
    
    // Create multiple layers of ripples
    float ripples = 0.0;
    
    // First ripple layer
    vec2 uvRipple1 = uv * 4.0;
    vec2 grid1 = floor(uvRipple1);
    vec2 center1 = grid1 + 0.5;
    
    // Get random ripple time offset for each cell
    float timeOffset1 = hash(grid1) * 5.0;
    float rippleTime1 = fract(t + timeOffset1);
    
    // Calculate distance from center
    float dist1 = distance(uvRipple1, center1);
    
    // Create ripple effect - expanding ring with fade out
    float ripple1 = smoothstep(0.5 * rippleTime1, 0.4 * rippleTime1, dist1) * 
                   smoothstep(0.0, 0.1 * rippleTime1, dist1) * 
                   (1.0 - rippleTime1); // Fade out with time
    
    ripples = max(ripples, ripple1 * 0.6);
    
    // Second ripple layer - smaller, more frequent
    vec2 uvRipple2 = uv * 8.0;
    vec2 grid2 = floor(uvRipple2);
    vec2 center2 = grid2 + 0.5;
    
    float timeOffset2 = hash(grid2) * 3.0;
    float rippleTime2 = fract(t * 1.5 + timeOffset2);
    
    float dist2 = distance(uvRipple2, center2);
    
    float ripple2 = smoothstep(0.4 * rippleTime2, 0.3 * rippleTime2, dist2) * 
                   smoothstep(0.0, 0.1 * rippleTime2, dist2) * 
                   (1.0 - rippleTime2);
    
    ripples = max(ripples, ripple2 * 0.3);
    
    return ripples;
}

void main() {
    // Sample map texture
    vec4 mapColor = texture2D(u_Tex0, v_TexCoord);
    
    // Rain color (dark blue-grey)
    vec3 rainColor = vec3(0.2, 0.23, 0.3);
    
    // Create different scaled UVs for rain patterns
    vec2 uv1 = v_WorldPos * 0.05;
    vec2 uv2 = v_WorldPos * 0.08;
    
    // Generate rain with different scales
    float rain1 = rainLine(uv1, u_Time);
    float rain2 = rainLine(uv2, u_Time * 0.9);
    
    // Combine rain layers
    float rain = rain1 * 0.5 + rain2 * 0.3;
    
    // Apply rain to the scene
    vec4 finalColor = mapColor;
    
    // Darken the scene (rainy atmosphere)
    finalColor.rgb = mix(finalColor.rgb, finalColor.rgb * (1.0 - DARKNESS), RAIN_DENSITY);
    
    // Desaturate the colors
    float luminance = dot(finalColor.rgb, vec3(0.299, 0.587, 0.114));
    finalColor.rgb = mix(finalColor.rgb, vec3(luminance), DESATURATION);
    
    // Add rain drops
    finalColor.rgb = mix(finalColor.rgb, rainColor, rain * RAIN_DENSITY * 0.3);
    
    // Add ripples
    float ripples = ripple(v_WorldPos * 0.02, u_Time);
    finalColor.rgb += ripples * RAIN_DENSITY * 0.2;
    
    // Add slight blue tint for rainy atmosphere
    finalColor.rgb = mix(finalColor.rgb, vec3(0.3, 0.35, 0.4), DARKNESS * 0.3);
    
    gl_FragColor = finalColor;
} 