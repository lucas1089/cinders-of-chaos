uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Bubble Blue parameters
float blueBubbleIntensity = 0.25; // Intensity of the blue bubble effect
float bubbleHighlightIntensity = 0.15; // Intensity of the bubble highlights
float popIntensity = 0.4; // Intensity of the pop effect

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
    float distFromCenter = v_TexCoord3.x; // Distance from center
    float normalizedAngle = v_TexCoord3.y; // Normalized angle
    
    // Create blue bubble effect
    // Add overall blue tint to the base color
    vec3 blueColor = vec3(0.2, 0.4, 1.0); // Rich blue
    baseColor.rgb = mix(baseColor.rgb, blueColor, blueBubbleIntensity);
    
    // Create bubble highlights (lighter patches that move)
    float highlight1 = sin(distFromCenter * 6.0 - u_Time * 0.7) * 0.5 + 0.5;
    float highlight2 = sin(distFromCenter * 8.0 - u_Time * 0.9) * 0.5 + 0.5;
    float highlightCombined = highlight1 * highlight2;
    highlightCombined = pow(highlightCombined, 3.0); // Make highlights more focused
    
    // Add bubble highlights
    vec3 highlightColor = vec3(0.5, 0.7, 1.0); // Light blue
    baseColor.rgb += highlightColor * highlightCombined * bubbleHighlightIntensity;
    
    // Create pop effect
    // Determine if this section is popping
    float popSection = floor(normalizedAngle * 8.0); // 8 sections
    float popSectionPhase = fract(popSection * 0.125 + u_Time * 0.2);
    
    // Pop flash - when bubbles pop, they emit a bright flash
    float popFlash = 0.0;
    if (popSectionPhase < 0.1) {
        popFlash = (0.1 - popSectionPhase) * 10.0; // Bright at start, fades quickly
        popFlash = popFlash * popFlash; // Quadratic falloff
    }
    
    // Add pop flash color (bright blue/white)
    vec3 popColor = mix(vec3(0.8, 0.9, 1.0), vec3(0.2, 0.5, 1.0), distFromCenter);
    baseColor.rgb += popColor * popFlash * popIntensity;
    
    // Add slight darkening with distance for more bubble-like appearance
    baseColor.rgb *= mix(1.0, 0.9, distFromCenter * 0.8);
    
    // Set output color
    gl_FragColor = baseColor;
} 