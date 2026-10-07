uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Split effect parameters
float glowSpeed = 2.0; // Speed of glow pulsing
float glowIntensity = 0.15; // Intensity of the split glow

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
    
    // Add a glowing effect along the split
    // Find if we're near the center (split area) of the texture
    float distFromCenter = abs(v_TexCoord.x - 0.5);
    float centerMask = smoothstep(0.1, 0.0, distFromCenter);
    
    // Create a pulsing glow effect
    float glowPulse = sin(u_Time * glowSpeed) * 0.5 + 0.5; // 0 to 1 pulse
    
    // Add a blue-white glow along the split
    vec3 glowColor = mix(vec3(0.2, 0.4, 1.0), vec3(1.0, 1.0, 1.0), glowPulse);
    baseColor.rgb += glowColor * centerMask * glowIntensity;
    
    // Set output color
    gl_FragColor = baseColor;
} 