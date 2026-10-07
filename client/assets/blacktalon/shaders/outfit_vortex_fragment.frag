uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Vortex parameters
float vortexDarkness = 0.7; // How dark the vortex gets
float energyGlowIntensity = 0.6; // Intensity of energy glow
float spiralHighlightIntensity = 0.5; // Intensity of spiral highlights

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get vortex information from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float spiralStrength = v_TexCoord3.y;
    
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
    
    // Create vortex time
    float vortexTime = u_Time * 0.8;
    
    // Create dark vortex color
    vec3 vortexCore = vec3(0.1, 0.0, 0.2); // Dark purple core
    vec3 vortexOuter = vec3(0.3, 0.1, 0.4); // Purple outer
    
    // Create energy colors for highlights
    vec3 energyColor1 = vec3(0.7, 0.2, 1.0); // Bright purple
    vec3 energyColor2 = vec3(0.3, 0.0, 0.6); // Dark purple
    
    // Mix vortex colors based on distance from center
    vec3 vortexColor = mix(vortexCore, vortexOuter, distFromCenter);
    
    // Calculate core darkness
    // Center is darkest, gradually returning to normal at the edges
    float darknessFactor = (1.0 - distFromCenter) * vortexDarkness;
    
    // Apply darkness to base color
    vec3 darkenedColor = mix(baseColor.rgb, vortexColor, darknessFactor);
    
    // Create spiral highlight effect
    // Using angle to create spiral patterns
    float angle = atan(v_TexCoord.y - 0.5, v_TexCoord.x - 0.5);
    
    // Create multiple spiral highlights that rotate
    float spiral1 = smoothstep(0.8, 1.0, sin(angle * 3.0 + distFromCenter * 10.0 - vortexTime * 2.0));
    float spiral2 = smoothstep(0.8, 1.0, sin(angle * 2.0 - distFromCenter * 8.0 + vortexTime * 1.5));
    
    // Combine spiral highlights
    float spiralHighlight = (spiral1 * 0.7 + spiral2 * 0.3) * spiralStrength;
    
    // Apply spiral highlight
    vec3 spiralColor = mix(energyColor2, energyColor1, spiralHighlight);
    darkenedColor = mix(darkenedColor, spiralColor, spiralHighlight * spiralHighlightIntensity);
    
    // Add center glow
    float centerGlow = smoothstep(0.4, 0.0, distFromCenter) * 
                       (sin(vortexTime * 3.0) * 0.5 + 0.5);
    darkenedColor += energyColor1 * centerGlow * energyGlowIntensity;
    
    // Add dark energy wisps
    // These are subtle dark energy strands that swirl around
    float wispAngle = angle + vortexTime;
    float wispPattern = sin(wispAngle * 8.0 + distFromCenter * 15.0);
    float wisp = smoothstep(0.7, 0.9, wispPattern) * smoothstep(0.95, 0.5, distFromCenter);
    
    // Apply dark wisps
    darkenedColor = mix(darkenedColor, vortexCore, wisp * 0.6);
    
    // Add subtle purple tint overall
    darkenedColor = mix(darkenedColor, darkenedColor * vec3(0.9, 0.8, 1.0), 0.2);
    
    // Final color
    gl_FragColor = vec4(darkenedColor, baseColor.a);
} 