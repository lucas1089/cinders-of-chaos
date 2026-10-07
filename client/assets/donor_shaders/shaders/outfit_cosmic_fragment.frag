uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying float v_FlowIntensity;
varying vec2 v_FlowDirection;
varying float v_CosmicPhase;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Cosmic flow parameters
float flowSpeed = 0.4;
float flowIntensity = 0.5;
float cosmicIntensity = 0.7;

// Cosmic color palette function
vec3 cosmicPalette(float t) {
    // Cosmic color palette
    vec3 green = vec3(0.0, 0.8, 0.4);
    vec3 yellow = vec3(0.9, 0.9, 0.2);
    vec3 purple = vec3(0.6, 0.2, 0.8);
    vec3 pink = vec3(0.9, 0.3, 0.6);
    vec3 white = vec3(0.9, 0.9, 0.9);
    vec3 blue = vec3(0.2, 0.4, 0.9);
    
    // Oscillate through cosmic colors
    t = fract(t); // Ensure t is 0 to 1
    
    if (t < 0.166) {
        return mix(green, yellow, t * 6.0);
    } else if (t < 0.333) {
        return mix(yellow, purple, (t - 0.166) * 6.0);
    } else if (t < 0.5) {
        return mix(purple, pink, (t - 0.333) * 6.0);
    } else if (t < 0.666) {
        return mix(pink, white, (t - 0.5) * 6.0);
    } else if (t < 0.833) {
        return mix(white, blue, (t - 0.666) * 6.0);
    } else {
        return mix(blue, green, (t - 0.833) * 6.0);
    }
}

// Enhanced plasma function with cosmic effects
vec4 cosmicPlasma(vec4 txt, vec2 uv, float speed) {
    float timeX = u_Time * speed;
    
    // Create flowing cosmic pattern
    float a = 1.1 + timeX * 1.5;
    float b = 0.5 + timeX * 1.2;
    float c = 8.4 + timeX * 1.0;
    float d = 3.2 + timeX * 0.8;
    float e = 5.7 + timeX * 1.3;
    
    float x = 2.0 * uv.x;
    float y = 2.0 * uv.y;
    
    // Generate cosmic plasma pattern
    float plasma = 
        sin(a + x) * 0.5 + 0.5 +
        sin(b - y) * 0.5 + 0.5 +
        sin((c + x + y) * 0.5) * 0.5 + 0.5 +
        sin(d + sqrt(x*x + y*y)) * 0.5 + 0.5 +
        sin(e + atan(y, x) * 2.0) * 0.5 + 0.5;
    
    plasma = plasma * 0.2; // Normalize to 0-1
    
    // Apply cosmic color palette
    vec3 cosmicColor = cosmicPalette(plasma + v_CosmicPhase);
    
    // Add cosmic sparkle
    float sparkle = sin(plasma * 15.0 + timeX * 3.0) * 0.5 + 0.5;
    cosmicColor += vec3(1.0) * sparkle * 0.3;
    
    // Mix with the texture
    return vec4(mix(txt.rgb, cosmicColor, flowIntensity), txt.a);
}

void main() {
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 flowTexture = texture2D(u_Tex0, v_TexCoord3);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Initialize with base color
    gl_FragColor = baseColor;
    
    if(texcolor.a > 0.9) {
        // Apply the cosmic plasma effect
        vec4 plasmaEffect = cosmicPlasma(baseColor, v_TexCoord + v_FlowDirection, flowSpeed);
        
        // Apply flow intensity
        gl_FragColor = mix(baseColor, plasmaEffect, v_FlowIntensity);
        
        // Add cosmic glow with color variation
        float glow = sin(u_Time * 1.2) * 0.15 + 0.15;
        vec3 glowColor = cosmicPalette(u_Time * 0.2);
        gl_FragColor.rgb += glowColor * glow * baseColor.a;
        
        // Apply cosmic edge highlight
        float edgeHighlight = 
            sin(v_TexCoord.x * 20.0 + u_Time * 2.0) * 0.5 + 0.5 + 
            cos(v_TexCoord.y * 15.0 + u_Time * 1.5) * 0.5 + 0.5;
        edgeHighlight = pow(edgeHighlight * 0.5, 3.0) * 0.1;
        
        // Add cosmic sparkle to edges
        float sparkle = sin(edgeHighlight * 15.0 + u_Time * 3.0) * 0.5 + 0.5;
        vec3 edgeColor = mix(cosmicPalette(u_Time * 0.1), vec3(1.0), sparkle);
        gl_FragColor.rgb += edgeColor * edgeHighlight;
        
        // Add cosmic star field effect
        float starField = sin(v_TexCoord.x * 100.0 + u_Time * 2.0) * 0.5 + 0.5;
        starField *= sin(v_TexCoord.y * 100.0 + u_Time * 1.5) * 0.5 + 0.5;
        starField = pow(starField, 10.0) * 0.5;
        gl_FragColor.rgb += vec3(1.0) * starField;
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 