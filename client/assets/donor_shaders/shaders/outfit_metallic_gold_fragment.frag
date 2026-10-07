uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Metallic gold parameters
float reflectionIntensity = 0.5; // Intensity of metallic reflections
float reflectionSharpness = 4.0; // Sharpness of reflection highlights
float goldShine = 0.6; // Gold shine factor

// Metal color definition
vec3 goldColor = vec3(1.0, 0.9, 0.4); // Rich gold color
vec3 goldHighlight = vec3(1.0, 0.98, 0.8); // Bright gold highlight

// Create smooth gold reflection pattern with rich flowing highlights
float smoothGoldPattern(vec2 position, float time) {
    // Create flowing gold-specific wave patterns (avoiding checkerboard)
    float wave1 = sin(position.x * 4.0 + position.y * 3.0 + time * 0.6) * 0.5 + 0.5;
    float wave2 = sin(position.x * 7.0 - position.y * 5.0 + time * 0.7) * 0.5 + 0.5;
    
    // Gold-specific swirl pattern
    float swirl = sin(atan(position.y, position.x) * 5.0 + length(position) * 10.0 + time * 0.5) * 0.5 + 0.5;
    
    // Create radial highlight patterns for gold
    float radial = length(position);
    float radialPattern = sin(radial * 8.0 - time * 0.5) * 0.5 + 0.5;
    
    // Add directional light reflection - more intense for gold
    float angle = atan(position.y, position.x);
    float lightReflection = pow(sin(angle * 3.0 + time * 0.8) * 0.5 + 0.5, 2.0);
    
    // Add fine detail pattern for gold
    float detail = sin(position.x * 20.0 + position.y * 15.0) * 0.5 + 0.5;
    
    // Combine all patterns for rich gold look without checkerboard
    return wave1 * 0.3 + wave2 * 0.2 + swirl * 0.2 + radialPattern * 0.15 + lightReflection * 0.2 + detail * 0.05;
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
    
    // Calculate gold effect using smooth pattern
    float goldPattern = smoothGoldPattern(normalizedPos, time);
    
    // Sharpen highlights
    goldPattern = pow(goldPattern, reflectionSharpness);
    
    // Apply gold color and reflection
    vec3 finalColor = mix(baseColor.rgb, goldColor, 0.6); // Strong gold base color
    
    // Add rich gold highlights
    finalColor += goldHighlight * goldPattern * reflectionIntensity * goldShine;
    
    // Add sparkle effect specific to gold (keep this as it looks nice)
    float sparkle = pow(sin(time * 3.0 + normalizedPos.x * 10.0 + normalizedPos.y * 8.0) * 0.5 + 0.5, 12.0);
    finalColor += goldHighlight * sparkle * 0.3;
    
    // Set output color
    gl_FragColor = vec4(finalColor, baseColor.a);
} 