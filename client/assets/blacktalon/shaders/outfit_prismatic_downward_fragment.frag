uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Prismatic Downward parameters
float prismaticIntensity = 0.7; // Intensity of prismatic effect
float glowIntensity = 0.5; // Intensity of moon glow

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
    
    // Get prismatic line information from vertex shader
    float linePattern = v_TexCoord3.x;
    float lineEffect = v_TexCoord3.y;
    
    // Create rainbow color based on line position (primarily falling down)
    // Use a blueish base for the color spectrum
    vec3 prismaticColor;
    
    // Create a color spectrum with more blues (falling water feel)
    float hue = linePattern;
    
    // Convert hue to RGB color - modified to favor blue tones
    float r = abs(hue * 6.0 - 3.0) - 1.0;
    float g = 2.0 - abs(hue * 6.0 - 2.0);
    float b = 2.0 - abs(hue * 6.0 - 4.0);
    prismaticColor = clamp(vec3(r, g, b), 0.0, 1.0);
    
    // Modify color to favor blues and aqua tones
    prismaticColor.r *= 0.7; // Reduce red
    prismaticColor.b *= 1.3; // Enhance blue
    
    // Add white highlight for shine on prismatic edges
    vec3 lineHighlight = vec3(1.0);
    
    // Combine prismatic color with white highlight at peaks
    vec3 finalLineColor = mix(prismaticColor, lineHighlight, lineEffect * 0.7);
    
    // Apply prismatic line effect with falloff based on y position
    // Lower on character = more effect (falling down emphasis)
    float yFalloff = (v_TexCoord.y - 0.3) * 1.5; // More intensity at bottom
    yFalloff = clamp(yFalloff, 0.2, 1.0);
    
    // Apply prismatic color to the base color
    baseColor.rgb = mix(baseColor.rgb, finalLineColor, lineEffect * prismaticIntensity * yFalloff);
    
    // Add moon-like glow effect - brighter at top, fading down
    float glowFalloff = 1.0 - v_TexCoord.y; // 1 at top, 0 at bottom
    glowFalloff = pow(glowFalloff, 2.0); // Sharper falloff
    
    // Moon glow color (slightly blue tinted)
    vec3 glowColor = vec3(0.9, 0.95, 1.0);
    
    // Apply subtle glow
    baseColor.rgb = mix(baseColor.rgb, glowColor, glowFalloff * glowIntensity * 0.3);
    
    // Add an extra brightness boost to lines
    baseColor.rgb += finalLineColor * lineEffect * 0.3;
    
    // Set output color
    gl_FragColor = baseColor;
} 