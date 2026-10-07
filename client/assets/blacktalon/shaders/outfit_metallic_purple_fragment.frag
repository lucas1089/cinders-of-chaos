uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Metallic purple parameters
float reflectionIntensity = 0.6; // Intensity of metallic reflections
float reflectionSharpness = 6.0; // Sharpness of reflection highlights
float mirrorEffect = 0.2; // Mirror-like reflection effect

// Metal color definition - Purple/Magenta for corruption (#8f0362)
vec3 purpleColor = vec3(0.56, 0.03, 0.38); // Dark magenta base
vec3 purpleHighlight = vec3(0.9, 0.3, 0.7); // Bright pink-purple highlight

// Create smooth purple reflection pattern with mirror-like quality
float smoothPurplePattern(vec2 position, float time) {
    // Create flowing, mirror-like wave patterns
    float wave1 = sin(position.x * 5.0 + position.y * 4.0 + time * 0.8) * 0.5 + 0.5;
    float wave2 = sin(position.x * 8.0 - position.y * 6.0 + time * 0.9) * 0.5 + 0.5;

    // Add precise, mirror-like reflections (sharp gradient transitions)
    float mirrorX = sin(position.x * 6.0 + time * 0.7);
    float mirrorY = sin(position.y * 7.0 - time * 0.6);
    float mirror = pow(abs(mirrorX * mirrorY), 0.5) * 0.7 + 0.3;

    // Create quick-moving highlight flashes
    float flash = pow(sin(position.x * 3.0 + position.y * 5.0 + time * 2.0) * 0.5 + 0.5, 8.0) * 0.8;

    // Add radial highlight pattern
    float radial = length(position);
    float radialPattern = sin(radial * 10.0 - time * 0.5) * 0.5 + 0.5;

    // Add moving directional highlights
    float angle = atan(position.y, position.x);
    float directional = pow(sin(angle * 4.0 + time) * 0.5 + 0.5, 3.0);

    // Combine all patterns for a realistic metallic look
    // Using max for some components to create sharp reflective surfaces
    float combined = wave1 * 0.2 + wave2 * 0.15;
    combined = max(combined, mirror * 0.3);
    combined = max(combined, flash);
    combined = max(combined, directional * 0.4);
    combined += radialPattern * 0.1;

    return combined;
}

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

    // Calculate purple pattern
    float purplePattern = smoothPurplePattern(normalizedPos, time);

    // Sharpen highlights
    purplePattern = pow(purplePattern, reflectionSharpness);

    // Apply purple color and reflection
    vec3 finalColor = mix(baseColor.rgb, purpleColor, 0.5); // Purple base color

    // Add sharp purple highlights
    finalColor += purpleHighlight * purplePattern * reflectionIntensity;

    // Add subtle dark magenta tint to shadows
    float shadowArea = 1.0 - purplePattern;
    finalColor += vec3(0.1, 0.0, 0.05) * shadowArea * 0.2;

    // Set output color
    gl_FragColor = vec4(finalColor, baseColor.a);
}
