uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Blessed parameters
float glowIntensity = 0.45; // Overall holy glow intensity
float rayIntensity = 0.5; // Intensity of golden rays
float pulseBrightness = 0.2; // Pulse brightness variation

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
    
    // Get distance from center and time from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float currentTime = v_TexCoord3.y;
    
    // Calculate angle for ray effect
    vec2 centeredCoord = v_TexCoord - vec2(0.5, 0.5);
    float angle = atan(centeredCoord.y, centeredCoord.x);
    
    // Create holy gold colors
    vec3 holyGold = vec3(1.0, 0.9, 0.4); // Bright gold
    vec3 holyWhite = vec3(1.0, 1.0, 0.95); // Almost white
    
    // Create pulsing glow that gets stronger at the edges
    float pulse = sin(currentTime * 0.8) * 0.5 + 0.5;
    float edgeGlow = smoothstep(0.0, 0.8, distFromCenter);
    float glowFactor = mix(0.2, 1.0, edgeGlow) * pulse * glowIntensity;
    
    // Apply glow
    baseColor.rgb = mix(baseColor.rgb, holyGold, glowFactor);
    
    // Create ray effect
    float rayAngle = sin(angle * 8.0 + currentTime * 1.2);
    float rayMask = pow(rayAngle * 0.5 + 0.5, 3.0); // Make rays sharper
    
    // Make rays stronger at the center and pulse
    float rayFactor = rayMask * (1.0 - distFromCenter) * rayIntensity * (pulse + 0.5);
    
    // Apply rays
    baseColor.rgb = mix(baseColor.rgb, holyWhite, rayFactor);
    
    // Add overall brightness pulsing
    float brightnessPulse = sin(currentTime * 0.6) * 0.5 + 0.5;
    baseColor.rgb += brightnessPulse * pulseBrightness * holyGold;
    
    // Add expanding ring effect
    float ringPhase = fract(currentTime * 0.4); // Slow expansion
    float ringRadius = ringPhase; // Use full radius (1.0)
    float ringWidth = 0.03; // Width of the ring
    
    // How close current pixel is to the ring
    float ringDistance = abs(distFromCenter - ringRadius);
    float ringFactor = 1.0 - smoothstep(0.0, ringWidth, ringDistance);
    
    // Apply ring
    baseColor.rgb += holyGold * ringFactor * 0.3;
    
    // Set output color
    gl_FragColor = baseColor;
} 