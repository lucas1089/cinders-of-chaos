uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Tall parameters
float gradientIntensity = 0.15; // Subtle gradient to emphasize height

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
    
    // Get normalized Y position from vertex shader
    float normalizedY = v_TexCoord3.x;
    
    // Apply subtle gradient effect to emphasize height
    // Slightly darker at bottom, brighter at top
    float gradientFactor = normalizedY * 2.0 - 1.0; // -1 to 1 range
    
    // Create subtle blue/cool tint at top and warm at bottom for atmosphere
    vec3 coolTint = vec3(0.8, 0.9, 1.0); // Slight blue tint
    vec3 warmTint = vec3(1.0, 0.9, 0.8); // Slight orange tint
    
    // Mix between warm and cool based on height
    vec3 tintColor = mix(warmTint, coolTint, normalizedY);
    
    // Apply the tint and gradient
    baseColor.rgb = mix(baseColor.rgb, baseColor.rgb * tintColor, gradientIntensity);
    baseColor.rgb += gradientFactor * gradientIntensity * 0.1; // Subtle brightness shift
    
    // Set output color
    gl_FragColor = baseColor;
} 