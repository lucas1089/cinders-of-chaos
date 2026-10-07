uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Aurora parameters
const float AURORA_SPEED = 2.0;            // Speed of aurora movement
const float AURORA_STRENGTH = 0.4;         // Strength of the aurora effect
const float SKY_DARKNESS = 0.3;            // Darkness of the sky
const float AURORA_WAVE_HEIGHT = 0.4;      // Height of aurora waves
const float AURORA_COMPLEXITY = 2.5;       // Complexity of the aurora patterns

// Aurora colors
const vec3 AURORA_COLOR1 = vec3(0.0, 0.8, 0.2);    // Green
const vec3 AURORA_COLOR2 = vec3(0.0, 0.4, 0.8);    // Blue
const vec3 AURORA_COLOR3 = vec3(0.8, 0.0, 0.8);    // Purple
const vec3 NIGHT_SKY = vec3(0.02, 0.05, 0.1);      // Dark blue night sky

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

// Create aurora pattern
vec3 auroraEffect(vec2 position, float time) {
    // Scale position for sky
    vec2 pos = position * 0.01;
    
    // Create wave effect
    float waveX = pos.x;
    float waveY = pos.y + sin(waveX * 1.5 + time * 0.5) * AURORA_WAVE_HEIGHT;
    
    // Create aurora bands with different frequencies
    float band1 = smoothstep(0.4, 0.6, sin(waveY * 2.0 + time * 0.2) * 0.5 + 0.5);
    float band2 = smoothstep(0.4, 0.6, sin(waveY * 3.0 - time * 0.3) * 0.5 + 0.5);
    float band3 = smoothstep(0.4, 0.6, sin(waveY * 1.0 + time * 0.4) * 0.5 + 0.5);
    
    // Add noise for more organic look
    vec2 noisePos = vec2(waveX * 0.8, waveY * 0.3) * AURORA_COMPLEXITY;
    float noise = snoise(noisePos + vec2(time * 0.2, time * 0.1)) * 0.5 + 0.5;
    noise = pow(noise, 1.5); // Make the noise more contrasty
    
    // Apply noise to bands
    band1 *= noise;
    band2 *= noise;
    band3 *= noise;
    
    // Fine curtain-like details
    float detail = smoothstep(0.3, 0.7, sin(waveY * 20.0 + time) * 0.5 + 0.5);
    detail *= noise;
    
    // Composite bands with colors
    vec3 aurora = AURORA_COLOR1 * band1 + AURORA_COLOR2 * band2 + AURORA_COLOR3 * band3;
    
    // Apply fine details to intensity
    aurora *= (0.8 + detail * 0.3);
    
    // Add vertical falloff (aurora is stronger higher in the sky)
    float verticalFalloff = smoothstep(0.0, 1.0, 1.0 - abs(pos.y * 0.1));
    aurora *= verticalFalloff;
    
    return aurora * AURORA_STRENGTH;
}

// Create a vignette effect
float vignette(vec2 uv, float intensity) {
    uv = uv * 2.0 - 1.0;
    return 1.0 - dot(uv, uv) * intensity;
}

void main() {
    // Sample the original texture
    vec4 color = texture2D(u_Tex0, v_TexCoord);
    
    // Calculate aurora effect
    vec3 aurora = auroraEffect(v_WorldPos, u_Time * AURORA_SPEED);
    
    // Darken the scene for night
    color.rgb *= (1.0 - SKY_DARKNESS);
    
    // Apply night sky color to upper areas
    float skyGradient = smoothstep(0.0, 1.0, 1.0 - abs(v_WorldPos.y * 0.01));
    color.rgb = mix(color.rgb, NIGHT_SKY, skyGradient * 0.6);
    
    // Apply aurora colors
    color.rgb += aurora;
    
    // Add slight vignette
    float vignetteEffect = vignette(v_TexCoord, 0.3);
    color.rgb *= vignetteEffect;
    
    gl_FragColor = color;
} 