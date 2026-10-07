// Rarity: Uncommon (Green) - 4-layer outline with glow
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

// Outline configuration
const float pixelSize = 1.0 / 64.0;

// Sample alpha in 8 directions at given distance
float sampleAlpha8(float dist) {
    float d = dist * pixelSize;
    return texture2D(u_Tex0, v_TexCoord + vec2(d, 0.0)).a +
           texture2D(u_Tex0, v_TexCoord + vec2(-d, 0.0)).a +
           texture2D(u_Tex0, v_TexCoord + vec2(0.0, d)).a +
           texture2D(u_Tex0, v_TexCoord + vec2(0.0, -d)).a +
           texture2D(u_Tex0, v_TexCoord + vec2(d * 0.707, d * 0.707)).a +
           texture2D(u_Tex0, v_TexCoord + vec2(-d * 0.707, d * 0.707)).a +
           texture2D(u_Tex0, v_TexCoord + vec2(d * 0.707, -d * 0.707)).a +
           texture2D(u_Tex0, v_TexCoord + vec2(-d * 0.707, -d * 0.707)).a;
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    
    // If pixel is part of the item, show it normally
    if (col.a > 0.5) {
        gl_FragColor = col;
        return;
    }
    
    // Pulsing animation
    float pulse = 0.85 + 0.15 * sin(u_Time * 3.0);
    
    // Sample at 4 distances for 4-layer outline
    float a1 = sampleAlpha8(1.0);  // Inner layer
    float a2 = sampleAlpha8(2.0);  // Middle layer
    float a3 = sampleAlpha8(3.0);  // Outer layer
    float a4 = sampleAlpha8(4.0);  // Glow layer
    
    // Green color scheme for Uncommon
    vec3 innerColor = vec3(0.4, 1.0, 0.4);   // Bright green (inner)
    vec3 midColor = vec3(0.2, 0.85, 0.2);    // Medium green (middle)
    vec3 outerColor = vec3(0.1, 0.65, 0.1);  // Darker green (outer)
    vec3 glowColor = vec3(0.6, 1.0, 0.6);    // Very bright green (glow)
    
    // Layer 1: Inner (brightest, closest to item)
    if (a1 > 0.0 && col.a < 1.0) {
        gl_FragColor = vec4(innerColor * pulse, 0.9);
        return;
    }
    
    // Layer 2: Middle
    if (a2 > 0.0 && col.a < 1.0) {
        gl_FragColor = vec4(midColor * pulse, 0.7);
        return;
    }
    
    // Layer 3: Outer
    if (a3 > 0.0 && col.a < 1.0) {
        gl_FragColor = vec4(outerColor * pulse, 0.5);
        return;
    }
    
    // Layer 4: Glow (softest, furthest from item)
    if (a4 > 0.0 && col.a < 1.0) {
        gl_FragColor = vec4(glowColor * pulse, 0.25);
        return;
    }
    
    gl_FragColor = col;
}
