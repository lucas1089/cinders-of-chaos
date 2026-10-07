uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Plasmic Toxic parameters
float blobColorIntensity = 0.7; // High intensity for toxic glow
float glowSpeed = 0.25; // Slower pulsing for ooze effect
float glowIntensity = 0.45; // Medium-high glow for toxic look
float blobColorShift = 0.15; // Subtle color shifting for sludge effect

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
    
    // Create blob pattern for toxic ooze
    float blobScale1 = 2.5; // Larger scale blobs for slime effect
    float blobScale2 = 4.0;
    float blobScale3 = 6.0;
    
    float blob1 = noise(vec2(v_TexCoord.x * blobScale1 + blobTime * 0.2, v_TexCoord.y * blobScale1 - blobTime * 0.15));
    float blob2 = noise(vec2(v_TexCoord.x * blobScale2 - blobTime * 0.1, v_TexCoord.y * blobScale2 + blobTime * 0.25));
    float blob3 = noise(vec2(v_TexCoord.x * blobScale3 + blobTime * 0.3, v_TexCoord.y * blobScale3 - blobTime * 0.1));
    
    // Combine blobs for slime effect
    float blobPattern = blob1 * 0.5 + blob2 * 0.3 + blob3 * 0.2;
    
    // Create bubbling effect
    float bubbleScale = 12.0;
    float bubbles = noise(vec2(v_TexCoord.x * bubbleScale + blobTime, v_TexCoord.y * bubbleScale - blobTime * 0.5));
    bubbles = smoothstep(0.6, 0.8, bubbles);
    
    // Mix bubbles into blob pattern
    blobPattern = mix(blobPattern, 1.0, bubbles * 0.3);
    
    // Make the blob pattern more distinct
    blobPattern = smoothstep(0.3, 0.7, blobPattern);
    
    // Toxic color palette
    // Color 1: Sickly Green
    vec3 color1 = vec3(0.2, 0.8, 0.1);
    // Color 2: Toxic Yellow
    vec3 color2 = vec3(0.8, 0.9, 0.1);
    // Color 3: Acid Green
    vec3 color3 = vec3(0.45, 0.95, 0.0);
    
    // Slower color shifting based on time
    float colorShift1 = sin(blobTime * 0.3) * 0.5 + 0.5;
    float colorShift2 = sin(blobTime * 0.2 + 1.0) * 0.5 + 0.5;
    float colorShift3 = sin(blobTime * 0.25 + 2.0) * 0.5 + 0.5;
    
    // Mix colors based on blob pattern for toxic sludge effect
    vec3 blobColor = mix(
        mix(color1, color2, colorShift1 * blobColorShift),
        mix(color2, color3, colorShift2 * blobColorShift),
        colorShift3
    );
    
    // Add bubble highlights (brighter centers)
    vec3 bubbleColor = vec3(0.7, 1.0, 0.3); // Bright toxic green
    blobColor = mix(blobColor, bubbleColor, bubbles * 0.5);
    
    // Apply toxic blob effect to base color
    baseColor.rgb = mix(baseColor.rgb, blobColor, blobPattern * blobColorIntensity);
    
    // Add toxic glow effect that pulses slowly
    float glow = sin(blobTime * glowSpeed) * 0.4 + 0.6;
    
    // Apply glow based on blob pattern
    vec3 glowColor = color3 * 1.4; // Brighter version of acid green
    baseColor.rgb += glowColor * blobPattern * glow * glowIntensity;
    
    // Add extra bubble highlights
    baseColor.rgb += bubbleColor * bubbles * 0.3;
    
    // Set output color
    gl_FragColor = baseColor;
} 