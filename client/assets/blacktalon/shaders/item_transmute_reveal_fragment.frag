// Transmute Transition - Reveal Shader (New Sprite - shows top portion)
// This shader reveals the NEW sprite from top to bottom during transition

uniform sampler2D u_Tex0;
uniform float u_Time;
uniform float u_var0;  // Transition progress: 0.0 = start, 1.0 = fully revealed
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;

// Configuration
const float LINE_WIDTH = 0.025;      // Width of the transition line
const float LINE_GLOW = 0.05;        // Glow around the line
const vec3 LINE_COLOR = vec3(1.0, 1.0, 1.0); // White/bright line
const float ALPHA_THRESHOLD = 0.01;  // Minimum alpha to render

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Calculate position (0 = top, 1 = bottom)
    float pixelY = 1.0 - v_TexCoord.y;

    // The reveal line position based on transition progress
    float revealPos = u_var0;

    // If pixel is BELOW the reveal line, discard it (show old sprite there)
    if (pixelY > revealPos + LINE_WIDTH) {
        discard;
    }

    vec4 finalColor = texColor;

    // Distance from the reveal line
    float distFromLine = abs(pixelY - revealPos);

    // Only apply glow effect to visible parts of sprite
    if (texColor.a > ALPHA_THRESHOLD) {
        // Add glowing line effect at the edge
        if (distFromLine < LINE_WIDTH + LINE_GLOW && pixelY <= revealPos + LINE_WIDTH) {
            float glowIntensity = 1.0 - (distFromLine / (LINE_WIDTH + LINE_GLOW));
            glowIntensity = pow(glowIntensity, 1.5);
            finalColor.rgb = mix(finalColor.rgb, LINE_COLOR, glowIntensity * 0.7);
        }

        // Add bright core line
        if (distFromLine < LINE_WIDTH) {
            float coreIntensity = 1.0 - (distFromLine / LINE_WIDTH);
            finalColor.rgb = mix(finalColor.rgb, LINE_COLOR, coreIntensity * 0.9);
        }
    }

    gl_FragColor = finalColor;
    if (gl_FragColor.a < ALPHA_THRESHOLD) discard;
}
