uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Rainbow Ripple parameters
float rainbowIntensity = 0.25; // Lower intensity for more original outfit visibility (75% transparency)
float rippleColorIntensity = 0.2; // Intensity of color change in ripples

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
    
    // Get time from vertex shader
    float currentTime = v_TexCoord3.x;
    float distFromCenter = v_TexCoord3.y;
    
    // Calculate rainbow hue from time
    float hue = fract(currentTime * 0.3); // Slower color cycle
    
    // Convert HSV to RGB - smooth rainbow colors
    vec3 rainbowColor;
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
    
    // Create ripple color enhancement based on distance
    float ripplePhase = distFromCenter * 5.0 - currentTime * 2.0;
    float rippleEffect = sin(ripplePhase * 3.14159 * 2.0) * 0.5 + 0.5;
    
    // Enhance specific color channels based on ripple
    rainbowColor *= 1.0 + rippleEffect * rippleColorIntensity;
    
    // Apply rainbow effect with lower intensity to preserve outfit details
    baseColor.rgb = mix(baseColor.rgb, rainbowColor, rainbowIntensity);
    
    // Set output color
    gl_FragColor = baseColor;
} 