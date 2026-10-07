uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Nightmare parameters
const float DESATURATION = 0.7;     // Amount of desaturation
const float VIGNETTE_STRENGTH = 0.5; // Darkness around edges
const float GLITCH_INTENSITY = 0.3;  // Intensity of glitch effect
const float RED_TINT = 0.3;          // Amount of red tint
const float FLICKER_SPEED = 1.2;     // Speed of light flickering

// Hash function for noise
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

// Generates static/noise pattern
float staticNoise(vec2 uv, float time) {
    float noise = noise2d(uv * 100.0 + time * 10.0);
    return step(0.8, noise) * 0.5; // Static appears in random spots
}

// Creates digital glitch blocks
float glitchBlock(vec2 uv, float time) {
    // Create horizontal glitch blocks that change over time
    float blockHeight = 0.05;
    float blockPos = floor(uv.y / blockHeight) * blockHeight;
    
    // Only some blocks glitch, and they change over time
    float glitchChance = noise2d(vec2(blockPos, time * 0.1));
    
    // Displacement amount
    float displacement = 0.0;
    if (glitchChance > 0.85) {
        displacement = sin(time * 20.0 + blockPos * 30.0) * 0.01;
    }
    
    return displacement;
}

// Vignette effect (darkness around edges)
float vignette(vec2 uv, float time) {
    // Calculate distance from center
    vec2 center = vec2(0.5);
    float dist = distance(uv, center);
    
    // Create pulsating vignette
    float vignettePulse = 1.0 + sin(time * 0.5) * 0.1;
    
    // Return vignette value
    return smoothstep(0.6 * vignettePulse, 0.2, dist);
}

void main() {
    // Animated time
    float time = u_Time * 0.5;
    
    // Apply glitch displacement to texture coordinates
    vec2 glitchUV = v_TexCoord;
    
    // Horizontal glitch blocks
    float blockGlitch = glitchBlock(glitchUV, time) * GLITCH_INTENSITY;
    glitchUV.x += blockGlitch;
    
    // Random short-duration glitches
    float randomGlitch = hash(floor(time * 2.0));
    if (randomGlitch > 0.93) {
        glitchUV.x += sin(glitchUV.y * 50.0) * 0.005 * GLITCH_INTENSITY;
    }
    
    // Sample texture with glitched coordinates
    vec4 color = texture2D(u_Tex0, glitchUV);
    
    // Add static/noise
    float staticNoiseValue = staticNoise(v_TexCoord, time) * GLITCH_INTENSITY;
    color.rgb += vec3(staticNoiseValue);
    
    // Desaturate the colors
    float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, vec3(luminance), DESATURATION);
    
    // Add flickering shadows (darkness)
    float flicker = 1.0 - (0.1 * sin(time * FLICKER_SPEED * 5.0) * sin(time * FLICKER_SPEED * 3.7));
    color.rgb *= flicker;
    
    // Add subtle red tint (especially in shadows)
    color.rgb = mix(color.rgb, color.rgb * vec3(1.0, 0.3, 0.3), RED_TINT * (1.0 - luminance));
    
    // Add vignette effect (darkness around edges)
    float vignetteEffect = vignette(v_TexCoord, time);
    color.rgb *= mix(0.4, 1.0, vignetteEffect);
    
    // Add random red flashes
    if (hash(floor(time * 1.2)) > 0.97) {
        float redFlash = 0.2 * sin(time * 20.0);
        color.r += redFlash;
    }
    
    gl_FragColor = color;
} 
