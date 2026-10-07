uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Thunderstorm parameters
const float RAIN_SPEED = 1.4;          // How fast the rain falls
const float RAIN_DENSITY = 0.6;        // How much rain
const float DARKNESS = 0.3;            // Darkness added by storm clouds
const float LIGHTNING_FREQUENCY = 0.04; // Much lower frequency (was 0.1)
const float LIGHTNING_CHANCE = 0.4;    // Lower chance of lightning (was 0.6)
const vec3 LIGHTNING_COLOR = vec3(1.0, 1.0, 0.9); // Slightly yellow-white

// Hash function
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float hash2D(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Rain line function
float rainLine(vec2 uv, float time) {
    // Rain streak parameters
    vec2 aspect = vec2(1.0, 6.0);  // Streaks are 6x taller than wide (heavy rain)
    float speed = time * RAIN_SPEED;
    
    // Calculate the grid for rain drops
    vec2 st = uv * aspect;
    
    // Offset each column of rain to make it look more natural
    float columnOffset = hash(floor(st.x)) * 0.8;
    
    // Create rain drops
    vec2 pos = vec2(
        fract(st.x),
        fract(st.y + speed + columnOffset)
    );
    
    // Draw the rain streak as a smooth line
    float rainDrop = smoothstep(0.0, 0.1, pos.y) * smoothstep(1.0, 0.9, pos.y);
    
    // Make some rain drops thinner than others
    float thickness = mix(0.03, 0.06, hash(st.x * 654.321));
    rainDrop *= smoothstep(thickness, 0.0, abs(pos.x - 0.5));
    
    return rainDrop;
}

// Lightning flash function with gentler transitions
float lightning(float time) {
    // Determine if lightning should strike based on time
    float timeSegment = floor(time / LIGHTNING_FREQUENCY);
    float segmentPos = fract(time / LIGHTNING_FREQUENCY);
    
    // Random lightning chance - lower chance than before
    float lightningChance = hash(timeSegment);
    
    if (lightningChance > (1.0 - LIGHTNING_CHANCE)) {
        // Lightning flash pattern - much more gradual transitions
        float flash = 0.0;
        
        // Primary flash - slower rise and fall
        if (segmentPos < 0.2) {
            // Gradual rise and fall using smoother curve
            flash = sin(segmentPos * 15.7) * 0.8;
            flash *= (1.0 - segmentPos * 5.0); // Fade out
        }
        
        // Secondary weaker flash - more spaced out in time
        if (segmentPos > 0.25 && segmentPos < 0.35) {
            flash = sin((segmentPos - 0.25) * 31.4) * 0.4;
            flash *= (1.0 - (segmentPos - 0.25) * 10.0); // Fade out
        }
        
        // Ensure flash is in range [0,1]
        flash = clamp(flash, 0.0, 0.8);
        
        return flash;
    }
    
    return 0.0;
}

void main() {
    // Animated time
    float time = u_Time;
    
    // Sample map texture
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    
    // Create different scaled UVs for rain patterns
    vec2 uv1 = v_WorldPos * 0.05;
    vec2 uv2 = v_WorldPos * 0.1;
    
    // Generate rain with different scales
    float rain1 = rainLine(uv1, time);
    float rain2 = rainLine(uv2, time * 0.9);
    
    // Combine rain layers
    float rain = rain1 * 0.5 + rain2 * 0.3;
    
    // Darken the scene (storm clouds)
    color.rgb = mix(color.rgb, color.rgb * (1.0 - DARKNESS), 0.8);
    
    // Add rain drops
    color.rgb = mix(color.rgb, vec3(0.2, 0.3, 0.35), rain * RAIN_DENSITY * 0.3);
    
    // Calculate lightning flash
    float flashIntensity = lightning(time);
    
    // Apply lightning flash to the scene with smoother transition
    if (flashIntensity > 0.0) {
        // Square the intensity to make the transition even smoother
        float smoothFlash = flashIntensity * flashIntensity;
        color.rgb = mix(color.rgb, LIGHTNING_COLOR, smoothFlash);
    }
    
    // Add slight blue tint for rainy atmosphere
    color.rgb = mix(color.rgb, vec3(0.3, 0.35, 0.45), DARKNESS * 0.3);
    
    gl_FragColor = color;
} 