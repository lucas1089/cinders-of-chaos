uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Inverted parameters
float inversePulsing = 0.2; // Amount of inversion pulsing
float edgeInversion = 0.3; // Extra inversion at edges
float edgeGlow = 0.2; // Amount of edge glow

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
    
    // Get normalized position and time from vertex shader
    vec2 normalizedPos = v_TexCoord3.xy;
    float time = u_Time;
    
    // Calculate distance from center for edge effects
    float distFromCenter = length(normalizedPos);
    
    // Create inversion effect that pulses
    float inversionPulse = sin(time * 0.8) * 0.5 + 0.5;
    float inversionFactor = inversionPulse * inversePulsing;
    
    // Add more inversion at edges
    inversionFactor += distFromCenter * edgeInversion;
    
    // Clamp inversion factor to ensure we don't go beyond full inversion
    inversionFactor = clamp(inversionFactor, 0.0, 1.0);
    
    // Invert colors based on inversion factor
    vec3 invertedColor = 1.0 - baseColor.rgb;
    vec3 finalColor = mix(baseColor.rgb, invertedColor, inversionFactor);
    
    // Add "dark world" purple/blue tint
    vec3 darkWorldTint = vec3(0.2, 0.0, 0.4); // Dark purple
    finalColor = mix(finalColor, finalColor * darkWorldTint, 0.3);
    
    // Add edge glow effect
    float edgeFactor = smoothstep(0.6, 1.0, distFromCenter);
    vec3 edgeColor = vec3(0.2, 0.0, 0.5); // Dark purple glow
    finalColor += edgeColor * edgeFactor * edgeGlow;
    
    // Add subtle pulse of light at edges
    float edgePulse = sin(time * 1.2 + distFromCenter * 5.0) * 0.5 + 0.5;
    edgePulse = pow(edgePulse, 3.0); // Sharpen pulse
    finalColor += vec3(0.3, 0.1, 0.5) * edgePulse * edgeFactor * 0.3;
    
    // Set output color
    gl_FragColor = vec4(finalColor, baseColor.a);
} 