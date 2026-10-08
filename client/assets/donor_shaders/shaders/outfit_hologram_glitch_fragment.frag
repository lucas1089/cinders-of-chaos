uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Hologram parameters
float hologramOpacity = 0.85;    // Base opacity of hologram
float scanlineCount = 30.0;      // Number of scanlines
float scanlineSpeed = 1.0;       // Scanline animation speed
float chromaticAberration = 0.003; // RGB color splitting amount
float flickerSpeed = 5.0;        // Speed of flicker effect
float noiseIntensity = 0.08;     // Intensity of noise pattern
float glowStrength = 0.4;        // Strength of edge glow

// Hash function for pseudo-random noise
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Create digital noise pattern
float digitalNoise(vec2 uv, float time) {
    float noise = hash(uv * 100.0 + time);
    
    // Create block patterns
    float blockSize = 0.05;
    vec2 blockUV = floor(uv / blockSize) * blockSize;
    float blockNoise = hash(blockUV * 50.0 + floor(time * 2.0));
    
    // Mix noise types for more interesting pattern
    return mix(noise, blockNoise, 0.7);
}

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample texture with normal coordinates
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Get distance and angle from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float angle = v_TexCoord3.y;
    
    // Create time variables
    float time = u_Time;
    float glitchTime = time * 3.0;
    
    // Create chromatic aberration effect (RGB color splitting)
    vec2 rOffset = vec2(chromaticAberration, 0.0);
    vec2 gOffset = vec2(0.0, 0.0);
    vec2 bOffset = vec2(-chromaticAberration, 0.0);
    
    // Sample with RGB offsets
    float r = texture2D(u_Tex0, v_TexCoord + rOffset).r;
    float g = texture2D(u_Tex0, v_TexCoord + gOffset).g;
    float b = texture2D(u_Tex0, v_TexCoord + bOffset).b;
    
    // Create new color with chromatic aberration
    vec3 chromatic = vec3(r, g, b);
    
    // Create scanline effect
    float scanlineY = fract(v_TexCoord.y * scanlineCount + time * scanlineSpeed);
    float scanline = smoothstep(0.5, 0.0, abs(scanlineY - 0.5)) * 0.5 + 0.5;
    
    // Create horizontal scanlines too, but more subtle
    float scanlineX = fract(v_TexCoord.x * scanlineCount * 0.5 + time * scanlineSpeed * 0.3);
    float scanlineH = smoothstep(0.5, 0.0, abs(scanlineX - 0.5)) * 0.5 + 0.5;
    scanline = mix(scanline, scanlineH, 0.3);
    
    // Create random noise
    float noise = digitalNoise(v_TexCoord, glitchTime) * noiseIntensity;
    
    // Create occasional strong horizontal glitch lines
    float horizontalGlitch = step(0.97, sin(time * 0.5) * 0.5 + 0.5);
    float glitchLine = step(0.95, sin(v_TexCoord.y * 100.0 + time * 10.0));
    float glitchIntensity = horizontalGlitch * glitchLine;
    
    // Create flicker effect
    float flicker = sin(time * flickerSpeed) * 0.1 + 0.9;
    
    // Create holographic color - cyan/blue tint
    vec3 holoColor = vec3(0.4, 1.0, 1.0);
    
    // Add color variation
    float colorVar = sin(angle * 2.0 + time) * 0.2 + 0.8;
    holoColor.b *= colorVar;
    
    // Create edge glow effect
    float edgeGlow = smoothstep(0.0, 0.8, distFromCenter) * smoothstep(1.0, 0.8, distFromCenter);
    
    // Apply hologram effect
    vec3 hologram = mix(chromatic, holoColor, 0.6);
    hologram = mix(hologram, holoColor, scanline * 0.3);
    hologram += noise * holoColor;
    hologram += glitchIntensity * vec3(1.0);
    hologram += edgeGlow * holoColor * glowStrength;
    hologram *= flicker;
    
    // Adjust opacity for hologram look - more transparent at edges
    float opacity = hologramOpacity * (1.0 - edgeGlow * 0.5);
    
    // Mix with original color
    baseColor.rgb = mix(baseColor.rgb, hologram, opacity);
    
    // Set output color
    gl_FragColor = baseColor;
} 