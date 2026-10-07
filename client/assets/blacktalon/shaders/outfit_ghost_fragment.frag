uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Ghost parameters
float transparency = 0.7; // Base transparency
float pulseAmount = 0.15; // Amount of transparency pulsing
float edgeFade = 0.25; // Edge fading intensity
vec3 ghostColor = vec3(0.85, 0.95, 1.0); // Slight blue tint

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
    
    // Apply outfit colors, but more subtly
    if(texcolor.r > 0.9) {
        baseColor *= mix(vec4(1.0), texcolor.g > 0.9 ? u_Color[0] : u_Color[1], 0.6);
    } else if(texcolor.g > 0.9) {
        baseColor *= mix(vec4(1.0), u_Color[2], 0.6);
    } else if(texcolor.b > 0.9) {
        baseColor *= mix(vec4(1.0), u_Color[3], 0.6);
    }
    
    // Get normalized position and time from vertex shader
    vec2 normalizedPos = v_TexCoord3.xy;
    float time = u_Time;
    
    // Calculate distance from center for edge fading
    float distFromCenter = length(normalizedPos);
    
    // Create pulsing transparency effect
    float pulse = sin(time * 0.7) * 0.5 + 0.5;
    float alpha = baseColor.a * (1.0 - transparency - pulse * pulseAmount);
    
    // Add edge fading (more transparent at edges)
    alpha *= (1.0 - distFromCenter * edgeFade);
    
    // Create subtle wisps/trails effect
    float wispPattern = sin(normalizedPos.y * 8.0 + time * 1.2 + normalizedPos.x * 5.0) * 0.5 + 0.5;
    wispPattern = smoothstep(0.4, 0.6, wispPattern);
    
    // Intensify bottom part alpha for trail effect
    float trailFactor = max(0.0, -normalizedPos.y * 2.0); // Stronger at bottom
    alpha *= mix(1.0, 0.7 + wispPattern * 0.3, trailFactor);
    
    // Add subtle color variations based on position and time
    float colorVariation = sin(normalizedPos.x * 3.0 + normalizedPos.y * 2.0 + time * 0.5) * 0.5 + 0.5;
    vec3 finalColor = mix(baseColor.rgb, ghostColor, 0.3 + colorVariation * 0.1);
    
    // Add subtle glow
    float glowPulse = sin(time * 0.5) * 0.5 + 0.5;
    finalColor += ghostColor * 0.1 * glowPulse;
    
    // Set output color with calculated alpha
    gl_FragColor = vec4(finalColor, alpha);
} 