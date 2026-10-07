uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Goofy Stretchy fragment parameters
float colorPulseSpeed = 2.0; // Speed of color pulsing
float colorPulseAmount = 0.15; // Amount of color change
float blushAmount = 0.3; // Amount of blush on cheeks

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
    
    // Extract data from v_TexCoord3
    float verticalPos = v_TexCoord3.x; // Vertical position in normalized space
    float stretchFactor = v_TexCoord3.y; // Current stretch amount
    
    // Add silly color pulse based on the stretch amount
    float colorPulse = sin(u_Time * colorPulseSpeed) * 0.5 + 0.5;
    
    // When stretched vertically, add more green
    // When stretched horizontally, add more red
    if (stretchFactor > 0.0) {
        // Stretched vertically - add green
        baseColor.g += stretchFactor * colorPulseAmount;
    } else {
        // Stretched horizontally - add red
        baseColor.r -= stretchFactor * colorPulseAmount; // stretchFactor is negative
    }
    
    // Add blush to "cheeks" - appears in middle of sprite when stretched
    vec2 leftCheek = vec2(0.3, 0.5);
    vec2 rightCheek = vec2(0.7, 0.5);
    
    float leftCheekDist = distance(v_TexCoord, leftCheek);
    float rightCheekDist = distance(v_TexCoord, rightCheek);
    
    // Blush intensity increases with stretch
    float blushIntensity = abs(stretchFactor) * blushAmount;
    
    // Apply blush to both cheeks
    if (leftCheekDist < 0.1) {
        float blushFactor = (0.1 - leftCheekDist) * 10.0 * blushIntensity;
        baseColor.r += blushFactor;
    }
    
    if (rightCheekDist < 0.1) {
        float blushFactor = (0.1 - rightCheekDist) * 10.0 * blushIntensity;
        baseColor.r += blushFactor;
    }
    
    // Add slight tint based on vertical position (upper part bluer, lower part redder)
    baseColor.r += -verticalPos * 0.1 * colorPulse;
    baseColor.b -= verticalPos * 0.1 * colorPulse;
    
    // Set output color
    gl_FragColor = baseColor;
} 