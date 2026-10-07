uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Retro pixelated parameters
float pixelSize = 0.03; // Size of pixels
float scanlineIntensity = 0.1; // Intensity of scanlines
float colorReduction = 0.85; // Color reduction for retro feel
float colorBleed = 0.02; // Color bleeding for CRT effect
float vignetteIntensity = 0.3; // Vignette effect intensity
float flickerAmount = 0.03; // Screen flicker amount

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Pixelate the texture coordinates
    vec2 pixelCoord = floor(v_TexCoord / pixelSize) * pixelSize;
    vec4 pixelatedColor = texture2D(u_Tex0, pixelCoord);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        pixelatedColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        pixelatedColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        pixelatedColor *= u_Color[3];
    }
    
    // Add scanline effect
    float scanline = sin(v_TexCoord.y * u_Resolution.y * 1.5) * 0.5 + 0.5;
    scanline = pow(scanline, 2.0); // Sharpen scanlines
    
    // Reduce color depth for retro feel
    vec3 reducedColor = floor(pixelatedColor.rgb * 8.0) / 8.0;
    
    // Add color bleeding (slight offset for RGB)
    vec4 bleedR = texture2D(u_Tex0, pixelCoord + vec2(colorBleed, 0.0));
    vec4 bleedB = texture2D(u_Tex0, pixelCoord - vec2(colorBleed, 0.0));
    
    // Create screen flicker
    float flicker = sin(u_Time * 8.0) * 0.5 + 0.5;
    flicker = 1.0 - (flicker * flickerAmount);
    
    // Apply slight chromatic aberration (RGB separation)
    vec3 finalColor = vec3(
        reducedColor.r * 1.05 + bleedR.r * 0.2,
        reducedColor.g,
        reducedColor.b * 1.05 + bleedB.b * 0.2
    );
    
    // Apply scanlines
    finalColor = mix(finalColor, finalColor * (1.0 - scanlineIntensity), scanline);
    
    // Apply flicker
    finalColor *= flicker;
    
    // Apply vignette effect (darker at corners)
    vec2 centeredCoord = v_TexCoord - vec2(0.5, 0.5);
    float vignette = 1.0 - dot(centeredCoord, centeredCoord) * 2.0;
    vignette = max(0.0, vignette);
    finalColor *= mix(1.0, vignette, vignetteIntensity);
    
    // Set output color
    gl_FragColor = vec4(finalColor, pixelatedColor.a);
} 