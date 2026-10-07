uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Metallic parameters
float reflectionIntensity = 0.4; // Intensity of metallic reflections
float reflectionSharpness = 5.0; // Sharpness of reflection highlights
float metalType = 0.0; // 0.0 = steel, 1.0 = gold, 2.0 = bronze, 3.0 = silver

// Metal color definitions
vec3 steelColor = vec3(0.8, 0.8, 0.9);
vec3 goldColor = vec3(1.0, 0.9, 0.4);
vec3 bronzeColor = vec3(0.8, 0.5, 0.2);
vec3 silverColor = vec3(0.95, 0.95, 1.0);

// Create smooth metallic reflection pattern
float smoothMetallicPattern(vec2 position, float time) {
    // Replace segmented pattern with smooth gradients
    
    // Create flowing wave patterns (avoiding checkerboard)
    float wave1 = sin(position.x * 5.0 + position.y * 3.0 + time * 0.6) * 0.5 + 0.5;
    float wave2 = sin(position.x * 7.0 - position.y * 4.0 + time * 0.8) * 0.5 + 0.5;
    float wave3 = sin(position.x * 3.0 + position.y * 6.0 - time * 0.7) * 0.5 + 0.5;
    
    // Combine waves for rich pattern
    float combined = mix(wave1, wave2, 0.5) * 0.7 + wave3 * 0.3;
    
    // Create radial highlight
    float radial = length(position);
    float radialPattern = sin(radial * 8.0 - time * 0.5) * 0.5 + 0.5;
    
    // Add directional light reflection
    float angle = atan(position.y, position.x);
    float lightReflection = pow(sin(angle * 2.0 + time) * 0.5 + 0.5, 3.0);
    
    // Combine all patterns for rich metallic look without checkerboard
    return combined * 0.5 + radialPattern * 0.3 + lightReflection * 0.2;
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
    
    // Calculate metallic effect using smooth pattern
    float metallicPattern = smoothMetallicPattern(normalizedPos, time);
    
    // Sharpen highlights
    metallicPattern = pow(metallicPattern, reflectionSharpness);
    
    // Choose metal color based on metalType
    vec3 metalColor;
    if(metalType < 0.5) {
        metalColor = steelColor; // Steel
    } else if(metalType < 1.5) {
        metalColor = goldColor; // Gold
    } else if(metalType < 2.5) {
        metalColor = bronzeColor; // Bronze
    } else {
        metalColor = silverColor; // Silver
    }
    
    // Apply metallic color and reflection
    vec3 finalColor = mix(baseColor.rgb, metalColor, 0.5); // Base metal color
    finalColor += metalColor * metallicPattern * reflectionIntensity; // Add reflections
    
    // Set output color
    gl_FragColor = vec4(finalColor, baseColor.a);
} 