uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Arcane parameters
float runeRotationSpeed = 0.2;
float runeScale = 6.0;
float runeOpacity = 0.65;
float glowIntensity = 0.4;
float glowPulseSpeed = 0.5;

// Vocation color presets (configurable)
// 0 = Blue (Sorcerer), 1 = Green (Druid), 2 = Red (Paladin), 3 = Yellow (Knight)
int vocationType = 0; 

// Get color based on vocation type
vec3 getVocationColor() {
    if (vocationType == 0) { // Sorcerer - blue
        return vec3(0.2, 0.4, 1.0);
    } else if (vocationType == 1) { // Druid - green
        return vec3(0.2, 0.9, 0.4);
    } else if (vocationType == 2) { // Paladin - red/orange
        return vec3(1.0, 0.4, 0.2);
    } else { // Knight - yellow
        return vec3(1.0, 0.9, 0.2);
    }
}

// Function to generate repeating rune patterns
float runePattern(vec2 uv, float seed) {
    uv = fract(uv);
    
    // Generate different rune shapes based on seed
    float pattern = 0.0;
    
    // Circular rune
    float circle = length(uv - vec2(0.5));
    
    // Line patterns
    float hline = abs(uv.y - 0.5);
    float vline = abs(uv.x - 0.5);
    
    // Cross pattern
    float cross = min(hline, vline);
    
    // Select pattern based on seed
    float s = fract(seed * 7.9) * 4.0;
    
    if (s < 1.0) {
        // Circle with inner details
        pattern = smoothstep(0.4, 0.35, circle) * smoothstep(0.15, 0.2, circle);
    } else if (s < 2.0) {
        // Cross pattern
        pattern = smoothstep(0.1, 0.05, cross);
    } else if (s < 3.0) {
        // Square with hole
        pattern = (step(0.15, uv.x) - step(0.85, uv.x)) * (step(0.15, uv.y) - step(0.85, uv.y));
        pattern *= 1.0 - ((step(0.35, uv.x) - step(0.65, uv.x)) * (step(0.35, uv.y) - step(0.65, uv.y)));
    } else {
        // Diamond shape
        float diamond = abs(uv.x - 0.5) + abs(uv.y - 0.5);
        pattern = smoothstep(0.45, 0.4, diamond);
    }
    
    return pattern;
}

void main() {
    // Sample original texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Skip processing completely transparent pixels
    if(baseColor.a < 0.01) discard;
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Get normalized position for rune placement
    vec2 normalizedPos = v_TexCoord3.xy;
    
    // Calculate rotation for runes
    float angle = u_Time * runeRotationSpeed;
    float c = cos(angle);
    float s = sin(angle);
    mat2 rotation = mat2(c, -s, s, c);
    
    // Get vocation glow color
    vec3 glowColor = getVocationColor();
    
    // Generate multiple rune layers with different rotations and scales
    float runeAlpha = 0.0;
    
    // Layer 1 - smaller, faster
    vec2 runePos1 = rotation * ((normalizedPos - 0.5) * runeScale * 1.2) + 0.5;
    runeAlpha += runePattern(runePos1, 0.1) * 0.5;
    
    // Layer 2 - medium, opposite rotation
    mat2 reverseRot = mat2(c, s, -s, c);
    vec2 runePos2 = reverseRot * ((normalizedPos - 0.5) * runeScale * 0.8) + 0.5;
    runeAlpha += runePattern(runePos2, 0.7) * 0.7;
    
    // Layer 3 - larger, slower
    vec2 runePos3 = rotation * ((normalizedPos - 0.5) * runeScale * 0.5) + 0.5;
    runeAlpha += runePattern(runePos3, 0.3) * 0.4;
    
    // Add pulsating glow effect
    float pulse = 0.7 + sin(u_Time * glowPulseSpeed) * 0.3;
    
    // Apply runes and glow to base color
    gl_FragColor = baseColor;
    
    // Only show runes on non-transparent parts of the outfit
    if (baseColor.a > 0.5) {
        // Add the arcane rune overlay
        gl_FragColor.rgb = mix(gl_FragColor.rgb, glowColor, runeAlpha * runeOpacity * pulse);
        
        // Add overall glow based on vocation
        gl_FragColor.rgb += glowColor * glowIntensity * pulse * 0.2;
    }
} 