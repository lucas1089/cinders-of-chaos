uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Turbo Rainbow parameters
float rainbowIntensity = 0.8; // Stronger rainbow effect
float rainbowBrightness = 1.2; // Brighter colors

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
    float distFromCenter = v_TexCoord3.y; // 0 at center, 1 at edge
    
    // Instead of discrete colors, use a continuous HSV-to-RGB conversion
    // This creates smooth transitions between a wide range of colors
    float hue = fract(currentTime * 0.5); // Full spectrum every 2 seconds
    
    // Convert HSV to RGB (hue, 1.0 saturation, 1.0 value)
    vec3 rainbowColor;
    
    // HSV to RGB conversion
    float h = hue * 6.0;
    float i = floor(h);
    float f = h - i;
    float p = 0.0;
    float q = 1.0 - f;
    float t = f;
    
    if(i == 0.0) rainbowColor = vec3(1.0, t, p);
    else if(i == 1.0) rainbowColor = vec3(q, 1.0, p);
    else if(i == 2.0) rainbowColor = vec3(p, 1.0, t);
    else if(i == 3.0) rainbowColor = vec3(p, q, 1.0);
    else if(i == 4.0) rainbowColor = vec3(t, p, 1.0);
    else rainbowColor = vec3(1.0, p, q);
    
    // Make colors brighter
    rainbowColor *= rainbowBrightness;
    
    // Add spatial variation - different parts of sprite change at different times
    float spatialOffset = v_TexCoord.x * 2.0 - v_TexCoord.y * 1.5;
    float spatialHue = fract(hue + spatialOffset * 0.2);
    
    // Convert the spatial hue to RGB
    vec3 spatialRainbow;
    h = spatialHue * 6.0;
    i = floor(h);
    f = h - i;
    q = 1.0 - f;
    t = f;
    
    if(i == 0.0) spatialRainbow = vec3(1.0, t, p);
    else if(i == 1.0) spatialRainbow = vec3(q, 1.0, p);
    else if(i == 2.0) spatialRainbow = vec3(p, 1.0, t);
    else if(i == 3.0) spatialRainbow = vec3(p, q, 1.0);
    else if(i == 4.0) spatialRainbow = vec3(t, p, 1.0);
    else spatialRainbow = vec3(1.0, p, q);
    
    spatialRainbow *= rainbowBrightness;
    
    // Mix the two rainbow effects
    vec3 finalRainbow = mix(rainbowColor, spatialRainbow, 0.3);
    
    // Apply rainbow effect to base color
    baseColor.rgb = mix(baseColor.rgb, finalRainbow, rainbowIntensity);
    
    // Add flashing highlights at random intervals
    float flashRate = 5.0; // Flashes per second
    float flashPhase = fract(currentTime * flashRate);
    if(flashPhase < 0.1) {
        float flashIntensity = 0.2 * (1.0 - flashPhase * 10.0);
        baseColor.rgb += flashIntensity;
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 