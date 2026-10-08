uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// High Bounce parameters for fragment
float colorBounceSpeed = 1.0; // Speed of color pulsing
float colorBounceAmount = 0.15; // Increased amount of color variation

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
    
    // Add a more pronounced color bounce effect with a bluish tint at the peak
    float colorPulse = sin(u_Time * colorBounceSpeed) * 0.5 + 0.5; // 0 to 1 pulse
    
    // Brighten colors near the peak of the bounce
    baseColor.rgb += mix(vec3(0.0), vec3(colorBounceAmount*0.8, colorBounceAmount, colorBounceAmount), colorPulse);
    
    // Set output color
    gl_FragColor = baseColor;
} 