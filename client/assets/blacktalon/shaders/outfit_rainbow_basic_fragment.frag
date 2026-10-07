uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Rainbow parameters
float rainbowIntensity = 0.6; // How strong the rainbow effect is

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
    
    // Get the current time from vertex shader
    float currentTime = v_TexCoord3.x;
    
    // Calculate which rainbow color we're currently on
    // We'll cycle through 6 main colors: red, orange, yellow, green, blue, purple
    float colorPhase = mod(currentTime, 3.0); // 0.5s per color = 3.0s full cycle
    
    // Define rainbow colors
    vec3 rainbow[6];
    rainbow[0] = vec3(1.0, 0.0, 0.0); // Red
    rainbow[1] = vec3(1.0, 0.5, 0.0); // Orange
    rainbow[2] = vec3(1.0, 1.0, 0.0); // Yellow
    rainbow[3] = vec3(0.0, 0.8, 0.0); // Green
    rainbow[4] = vec3(0.0, 0.0, 1.0); // Blue
    rainbow[5] = vec3(0.5, 0.0, 0.8); // Purple
    
    // Determine which color index we're on
    // Use float math for GLSL ES compatibility
    float colorIndexF = floor(colorPhase / 0.5); // Each color lasts 0.5 seconds
    colorIndexF = min(colorIndexF, 5.0); // Safety check
    int colorIndex = int(colorIndexF);

    // Get the current rainbow color
    vec3 rainbowColor = rainbow[colorIndex];
    
    // Apply rainbow effect to base color
    baseColor.rgb = mix(baseColor.rgb, rainbowColor, rainbowIntensity);
    
    // Ensure we don't wash out the texture completely
    float luminance = dot(baseColor.rgb, vec3(0.299, 0.587, 0.114));
    baseColor.rgb = mix(vec3(luminance), baseColor.rgb, 0.7);
    
    // Set output color
    gl_FragColor = baseColor;
} 