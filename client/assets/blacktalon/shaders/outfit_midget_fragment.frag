uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Midget parameters
float rosyness = 0.15; // Add cute rosy cheeks to midget

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
    
    // Normalized coordinates (0,0 at center, -1 to 1 range)
    vec2 normalizedCoord = v_TexCoord * 2.0 - 1.0;
    
    // Add rosy cheeks - on left and right sides near middle of face
    float leftCheek = smoothstep(0.15, 0.0, distance(normalizedCoord, vec2(-0.5, -0.2)));
    float rightCheek = smoothstep(0.15, 0.0, distance(normalizedCoord, vec2(0.5, -0.2)));
    
    // Apply rosy cheek coloring 
    float cheeks = leftCheek + rightCheek;
    baseColor.rgb = mix(baseColor.rgb, vec3(1.0, 0.4, 0.4), cheeks * rosyness);
    
    // Slightly brighten the overall colors for cute effect
    baseColor.rgb *= 1.1;
    
    // Set output color
    gl_FragColor = baseColor;
} 