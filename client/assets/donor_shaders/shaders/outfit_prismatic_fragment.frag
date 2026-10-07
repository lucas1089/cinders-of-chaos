uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Prismatic parameters - adjusted for smoother appearance
float lineSpeed = 0.5; // Slower speed for less jagged movement
float lineWidth = 0.12; // Wider lines for smoother appearance
float lineBlur = 0.08; // Added blur parameter for softer edges
float lineIntensity = 0.4; // Balanced intensity for visible but not harsh rainbow
float moonGlowIntensity = 0.2; // Keep the same
float moonPulseSpeed = 0.2; // Slower, more subtle pulse
float prismaticIntensity = 0.35; // Consistent rainbow effect
float lineBlending = 0.7; // Balanced for visible but soft effect

// Enhanced helper function for smoother line transitions with blur
float smoothLine(float pos, float width, float blur) {
    float halfWidth = width * 0.5;
    // Use a more gradual transition with additional blur parameter
    return smoothstep(0.0, blur + halfWidth, pos) * smoothstep(1.0, 1.0 - (blur + halfWidth), pos);
}

// Gaussian-like blur function
float gaussianBlur(float dist, float radius) {
    return exp(-(dist * dist) / radius);
}

void main() {
    // Sample texture with normal coordinates - no boundary check initially
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Save original alpha for later blending (only apply effect where texture exists)
    float originalAlpha = baseColor.a;
    
    // Extract position info from vertex shader
    float distFromCenter = v_TexCoord3.x; // For moon glow
    float normalizedAngle = v_TexCoord3.y; // For diagonal lines
    
    // Create smoother diagonal lines effect
    float diagonalPos1 = normalizedAngle * 3.0 - u_Time * lineSpeed; // Reduced frequency
    float diagonalPos2 = normalizedAngle * 2.5 + u_Time * lineSpeed * 0.7; // Offset second set
    
    // Anti-aliased lines with smoother transitions
    float linePattern1 = fract(diagonalPos1);
    float linePattern2 = fract(diagonalPos2);
    
    // Create smoother line patterns with enhanced anti-aliasing and blur
    float line1 = smoothLine(linePattern1, lineWidth, lineBlur);
    float line2 = smoothLine(linePattern2, lineWidth * 0.8, lineBlur * 1.5); // Slightly thinner secondary lines with more blur
    
    // Fade lines out near the edges of the sprite for smoother transitions
    float edgeFade = 1.0 - smoothstep(0.7, 1.0, distFromCenter);
    line1 *= edgeFade;
    line2 *= edgeFade;
    
    // Apply additional gaussian-like blur to soften the lines
    float blur1 = gaussianBlur(abs(linePattern1 - 0.5) * 2.0, 0.4);
    float blur2 = gaussianBlur(abs(linePattern2 - 0.5) * 2.0, 0.4);
    
    // Combine lines with smoother blending
    float combinedLines = line1 * 0.6 + line2 * 0.4;
    float combinedBlur = blur1 * 0.3 + blur2 * 0.2;
    combinedLines = max(combinedLines, combinedBlur * 0.5);
    
    // Create prismatic rainbow effect with smoother, slower changes
    float hueShift = fract(normalizedAngle * 0.8 + u_Time * 0.03); // Slower color changes
    
    // Create smoother rainbow color from hue
    vec3 rainbow;
    float h = hueShift * 6.0;
    float i = floor(h);
    float f = h - i;
    
    // Smoother color interpolation
    f = smoothstep(0.0, 1.0, f); // Smooth the transition between hues
    float q = 1.0 - f;
    
    if (i == 0.0) rainbow = vec3(1.0, f, 0.0);
    else if (i == 1.0) rainbow = vec3(q, 1.0, 0.0);
    else if (i == 2.0) rainbow = vec3(0.0, 1.0, f);
    else if (i == 3.0) rainbow = vec3(0.0, q, 1.0);
    else if (i == 4.0) rainbow = vec3(f, 0.0, 1.0);
    else rainbow = vec3(1.0, 0.0, q);
    
    // Make the rainbow more vivid (less pastel)
    rainbow = mix(rainbow, vec3(1.0), 0.45); // Less pastel for more vibrant colors
    
    // Apply the diagonal lines with rainbow colors and smoother blending
    vec3 lineColor = rainbow * (combinedLines * lineIntensity + combinedBlur * 0.3);
    baseColor.rgb = mix(baseColor.rgb, baseColor.rgb + lineColor, lineBlending);
    
    // Apply prismatic color shift to the base texture with smoother blending
    vec3 prismaticColor = rainbow * 0.7 + 0.5; // More vivid version
    baseColor.rgb = mix(baseColor.rgb, baseColor.rgb * prismaticColor, prismaticIntensity);
    
    // Add smoothed moon glow effect
    float moonPulse = sin(u_Time * moonPulseSpeed) * 0.4 + 0.6; // Less pulsation
    float moonGlow = (1.0 - distFromCenter) * moonPulse; // Center is brightest
    // Smoother falloff for moon glow
    moonGlow = max(0.0, moonGlow * 1.8 - 0.4); // Adjusted for smoother transition
    moonGlow = smoothstep(0.0, 1.0, moonGlow); // Additional smoothing
    
    // Softer moon color
    vec3 moonColor = vec3(0.85, 0.92, 1.0);
    
    // Apply moon glow with smoother blending
    baseColor.rgb += moonColor * moonGlow * moonGlowIntensity;
    
    // Set output color - maintain original alpha for proper blending
    gl_FragColor = vec4(baseColor.rgb, originalAlpha);
} 