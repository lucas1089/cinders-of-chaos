uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Plasmic Fantasy parameters
float blobColorIntensity = 0.65; // Intensity of blob coloring
float glowSpeed = 0.5; // Speed of glow pulsing
float glowIntensity = 0.3; // Intensity of glow effect
float blobColorShift = 0.2; // How much the blob colors shift

// Simple hash function
float hash(float p) {
    return fract(sin(p * 591.32) * 43758.5453);
}

// Simple noise function
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 157.0;
    return mix(
        mix(hash(n + 0.0), hash(n + 1.0), f.x),
        mix(hash(n + 157.0), hash(n + 158.0), f.x),
        f.y
    );
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
    
    // Extract data from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float blobTime = v_TexCoord3.y;
    
    // Create blob pattern
    // Use noise-based pattern for organic-looking blobs
    float blobScale1 = 3.0;
    float blobScale2 = 5.0;
    float blobScale3 = 8.0;
    
    float blob1 = noise(vec2(v_TexCoord.x * blobScale1 + blobTime * 0.3, v_TexCoord.y * blobScale1 - blobTime * 0.5));
    float blob2 = noise(vec2(v_TexCoord.x * blobScale2 - blobTime * 0.4, v_TexCoord.y * blobScale2 + blobTime * 0.2));
    float blob3 = noise(vec2(v_TexCoord.x * blobScale3 + blobTime * 0.1, v_TexCoord.y * blobScale3 - blobTime * 0.3));
    
    // Combine blobs of different sizes for a more organic lava lamp effect
    float blobPattern = blob1 * 0.5 + blob2 * 0.3 + blob3 * 0.2;
    
    // Make the blob pattern more distinct with contrast
    blobPattern = smoothstep(0.3, 0.7, blobPattern);
    
    // Create color shifting effect
    // Color 1: Purple/Magenta
    vec3 color1 = vec3(0.8, 0.2, 0.8);
    // Color 2: Cyan/Blue
    vec3 color2 = vec3(0.2, 0.6, 0.9);
    // Color 3: Green/Yellow
    vec3 color3 = vec3(0.8, 0.9, 0.2);
    
    // Color shifting based on time
    float colorShift1 = sin(blobTime * 0.5) * 0.5 + 0.5;
    float colorShift2 = sin(blobTime * 0.3 + 1.0) * 0.5 + 0.5;
    float colorShift3 = sin(blobTime * 0.4 + 2.0) * 0.5 + 0.5;
    
    // Mix colors based on blob pattern and time
    vec3 blobColor = mix(
        mix(color1, color2, colorShift1 * blobColorShift),
        mix(color2, color3, colorShift2 * blobColorShift),
        colorShift3
    );
    
    // Apply glowing blob effect to base color
    baseColor.rgb = mix(baseColor.rgb, blobColor, blobPattern * blobColorIntensity);
    
    // Add glow effect that pulses
    float glow = sin(blobTime * glowSpeed) * 0.5 + 0.5;
    
    // Apply glow based on blob pattern
    vec3 glowColor = blobColor * 1.5; // Brighter version of blob color
    baseColor.rgb += glowColor * blobPattern * glow * glowIntensity;
    
    // Set output color
    gl_FragColor = baseColor;
} 