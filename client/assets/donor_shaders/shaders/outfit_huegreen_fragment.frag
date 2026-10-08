uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying float v_FlowIntensity;
varying vec2 v_FlowDirection;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Green hue flow parameters
float flowSpeed = 0.4;
float flowIntensity = 0.5;
float holoIntensity = 0.7;

// Enhanced green hue palette function
vec3 greenHuePalette(float t) {
    // Expanded green palette
    vec3 emerald = vec3(0.0, 0.8, 0.4);
    vec3 jade = vec3(0.0, 0.6, 0.3);
    vec3 forest = vec3(0.0, 0.4, 0.2);
    vec3 mint = vec3(0.4, 0.9, 0.6);
    vec3 lime = vec3(0.5, 0.9, 0.2);
    vec3 teal = vec3(0.0, 0.7, 0.7);
    vec3 sage = vec3(0.5, 0.8, 0.5);
    vec3 olive = vec3(0.4, 0.5, 0.2);
    
    // Oscillate between green variations
    t = fract(t); // Ensure t is 0 to 1
    
    if (t < 0.125) {
        return mix(emerald, jade, t * 8.0);
    } else if (t < 0.25) {
        return mix(jade, forest, (t - 0.125) * 8.0);
    } else if (t < 0.375) {
        return mix(forest, mint, (t - 0.25) * 8.0);
    } else if (t < 0.5) {
        return mix(mint, lime, (t - 0.375) * 8.0);
    } else if (t < 0.625) {
        return mix(lime, teal, (t - 0.5) * 8.0);
    } else if (t < 0.75) {
        return mix(teal, sage, (t - 0.625) * 8.0);
    } else if (t < 0.875) {
        return mix(sage, olive, (t - 0.75) * 8.0);
    } else {
        return mix(olive, emerald, (t - 0.875) * 8.0);
    }
}

// Enhanced plasma function with holographic effects
vec4 greenPlasma(vec4 txt, vec2 uv, float speed) {
    float timeX = u_Time * speed;
    
    // Create flowing plasma-like pattern
    float a = 1.1 + timeX * 1.5;
    float b = 0.5 + timeX * 1.2;
    float c = 8.4 + timeX * 1.0;
    float d = 3.2 + timeX * 0.8;
    
    float x = 2.0 * uv.x;
    float y = 2.0 * uv.y;
    
    // Generate plasma pattern with more complexity
    float plasma = 
        sin(a + x) * 0.5 + 0.5 +
        sin(b - y) * 0.5 + 0.5 +
        sin((c + x + y) * 0.5) * 0.5 + 0.5 +
        sin(d + sqrt(x*x + y*y)) * 0.5 + 0.5;
    
    plasma = plasma * 0.25; // Normalize to 0-1
    
    // Apply green hue palette
    vec3 greenColor = greenHuePalette(plasma);
    
    // Add holographic kickback
    float holoKick = sin(plasma * 10.0 + timeX * 2.0) * 0.5 + 0.5;
    greenColor += vec3(0.0, holoKick * 0.3, holoKick * 0.2);
    
    // Mix with the texture
    return vec4(mix(txt.rgb, greenColor, flowIntensity), txt.a);
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
        // Apply the green plasma effect
        vec4 plasmaEffect = greenPlasma(baseColor, v_TexCoord + v_FlowDirection, flowSpeed);
        
        // Apply flow intensity
        gl_FragColor = mix(baseColor, plasmaEffect, v_FlowIntensity);
        
        // Add enhanced glow with color variation
        float glow = sin(u_Time * 1.2) * 0.15 + 0.15;
        vec3 glowColor = greenHuePalette(u_Time * 0.2);
        gl_FragColor.rgb += glowColor * glow * baseColor.a;
        
        // Apply edge highlight for flowing effect with holographic kick
        float edgeHighlight = 
            sin(v_TexCoord.x * 20.0 + u_Time * 2.0) * 0.5 + 0.5 + 
            cos(v_TexCoord.y * 15.0 + u_Time * 1.5) * 0.5 + 0.5;
        edgeHighlight = pow(edgeHighlight * 0.5, 3.0) * 0.1;
        
        // Add holographic kickback to edges
        float holoKick = sin(edgeHighlight * 15.0 + u_Time * 3.0) * 0.5 + 0.5;
        vec3 edgeColor = mix(vec3(0.2, 0.8, 0.4), vec3(0.0, 0.9, 0.6), holoKick);
        gl_FragColor.rgb += edgeColor * edgeHighlight;
        
        // Add holographic scan lines
        float scanLine = sin(v_TexCoord.y * 50.0 + u_Time * 2.0) * 0.5 + 0.5;
        scanLine = pow(scanLine, 2.0) * 0.1;
        gl_FragColor.rgb += vec3(0.0, scanLine * 0.5, scanLine * 0.3);
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 