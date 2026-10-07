uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Pixelation parameters - reduced for small sprites
float pixelSize = 0.004; // REDUCED: Much smaller pixel size (was 0.008)
float colorDepth = 5.0; // INCREASED: Higher color depth for more colors (was 3.0)
float animationSpeed = 0.2; // REDUCED: Even slower animation (was 0.3)

void main() {
    // Only apply pixelation if we're dealing with the actual outfit (alpha > 0)
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    
    // Check if we're actually on the sprite 
    if(originalColor.a < 0.01) {
        discard; // Skip transparent pixels
    }
    
    // Calculate animated pixel size (very subtle animation)
    float animatedPixelSize = pixelSize * (0.95 + 0.05 * sin(u_Time * animationSpeed)); // REDUCED: Less animation (was 0.9 + 0.1)
    
    // Calculate pixelated texture coordinates
    vec2 pixelCoord = floor(v_TexCoord / animatedPixelSize) * animatedPixelSize;
    
    // Blend between pixelated and original - new addition for subtler effect
    vec4 pixelatedColor = texture2D(u_Tex0, pixelCoord);
    float pixelBlend = 0.4; // 40% pixelated, 60% original
    vec4 baseColor = mix(originalColor, pixelatedColor, pixelBlend);
    
    // Apply color depth reduction - keep alpha intact
    float alpha = baseColor.a;
    baseColor.rgb = floor(baseColor.rgb * colorDepth) / colorDepth;
    baseColor.a = alpha; // Restore original alpha
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Set output color
    gl_FragColor = baseColor;
    
    // Add very subtle scanlines effect
    float scanline = sin(v_TexCoord.y * 50.0) * 0.01 + 0.99; // REDUCED: Much more subtle (was 60.0, 0.03)
    gl_FragColor.rgb *= scanline;
    
    // Add subtle CRT-like distortion at the edges
    vec2 distFromCenter = abs(v_TexCoord - vec2(0.5, 0.5)) * 2.0;
    float vignette = 1.0 - dot(distFromCenter, distFromCenter) * 0.1; // REDUCED: Was 0.2
    gl_FragColor.rgb *= vignette;
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 