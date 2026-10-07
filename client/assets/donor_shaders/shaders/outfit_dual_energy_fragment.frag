uniform mat4 u_Color;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform float u_Time;

varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
varying vec4 v_Color;

// Blending parameters
float blendSpeed = 0.3;     // Speed of the blend oscillation
float noiseAmount = 0.15;   // Amount of noise to add
float energyIntensity = 0.6; // Intensity of the energy effect

// RGB to HSV conversion function
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB conversion function
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Simple random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Function to invert colors
vec3 invertColor(vec3 color) {
    return vec3(1.0) - color;
}

// Function to create energy effect
vec3 energyEffect(vec2 uv, float time, vec3 color) {
    // Create wavy energy pattern
    float wave1 = sin(uv.x * 20.0 + time * 2.0) * 0.5 + 0.5;
    float wave2 = sin(uv.y * 15.0 + time * 1.5) * 0.5 + 0.5;
    float wave3 = sin((uv.x + uv.y) * 10.0 + time * 3.0) * 0.5 + 0.5;
    
    // Combine waves
    float energyPattern = (wave1 + wave2 + wave3) / 3.0;
    
    // Create pulsing effect
    float pulse = sin(time * 1.5) * 0.2 + 0.8;
    
    // Apply energy color (inverted)
    vec3 energyColor = invertColor(color) * energyPattern * pulse;
    
    return energyColor;
}

void main()
{
    // Sample the original texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample both trippy textures
    vec4 texture1 = texture2D(u_Tex1, v_TexCoord3);
    vec4 texture2 = texture2D(u_Tex2, v_TexCoord4);
    
    // Apply outfit colors based on the texture channels
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Set initial output color
    gl_FragColor = baseColor;
    
    if(texcolor.a > 0.9) {
        // Create oscillating blend amount with limited range
        float blendAmount = sin(u_Time * blendSpeed) * 0.4 + 0.5;
        
        // Add some noise to the blend for more interesting patterns
        float noiseValue = random(v_TexCoord3 * 10.0 + u_Time * 0.1) * noiseAmount;
        blendAmount = clamp(blendAmount + noiseValue, 0.2, 0.8);
        
        // Blend the two textures
        vec3 blendedTexture = mix(texture1.rgb, texture2.rgb, blendAmount);
        
        // Get inverted energy effect based on the first texture
        vec3 energyColors = energyEffect(v_TexCoord, u_Time, texture1.rgb);
        
        // Mix base color and blended texture
        vec3 finalColor = mix(baseColor.rgb, blendedTexture, 0.6);
        
        // Add energy effect
        finalColor += energyColors * energyIntensity;
        
        // Add edge highlight for energy effect
        float edge = (1.0 - texture1.r) * (1.0 - texture1.g) * (1.0 - texture1.b);
        edge = pow(edge, 4.0) * 0.5;
        finalColor += invertColor(texture1.rgb) * edge;
        
        // Ensure we don't exceed the maximum brightness
        finalColor = min(finalColor, vec3(1.0));
        
        gl_FragColor = vec4(finalColor, baseColor.a);
    }
    
    // Discard transparent pixels
    if(gl_FragColor.a < 0.01) discard;
} 