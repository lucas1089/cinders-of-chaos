uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Neon parameters
float glowIntensity = 0.9;
float pulseSpeed = 1.2;
float edgeThreshold = 0.01;  // Much more sensitive edge detection
float glowRadius = 0.2;      // Larger glow
float innerGlowStrength = 0.5;  // Higher inner glow

// Purple neon colors only
vec3 getNeonColor(float value) {
    // Purple neon palette
    vec3 darkPurple = vec3(0.3, 0.0, 0.5);
    vec3 brightPurple = vec3(0.6, 0.0, 1.0);
    vec3 magenta = vec3(1.0, 0.0, 1.0);
    vec3 hotPink = vec3(1.0, 0.0, 0.7);
    
    // Cycle through colors
    value = fract(value);
    
    if (value < 0.25) {
        return mix(darkPurple, brightPurple, value * 4.0);
    } else if (value < 0.5) {
        return mix(brightPurple, magenta, (value - 0.25) * 4.0);
    } else if (value < 0.75) {
        return mix(magenta, hotPink, (value - 0.5) * 4.0);
    } else {
        return mix(hotPink, darkPurple, (value - 0.75) * 4.0);
    }
}

// Edge detection for neon glow - improved version
float detectEdge(sampler2D tex, vec2 uv, vec2 step) {
    // Sample 9 points around the current pixel
    float center = texture2D(tex, uv).a;
    
    // Skip edge detection for transparent areas
    if (center < 0.01) return 0.0;
    
    // Sample the 8 neighboring pixels for better edge detection
    float tl = texture2D(tex, uv + vec2(-step.x, -step.y)).a;
    float t = texture2D(tex, uv + vec2(0.0, -step.y)).a;
    float tr = texture2D(tex, uv + vec2(step.x, -step.y)).a;
    float r = texture2D(tex, uv + vec2(step.x, 0.0)).a;
    float br = texture2D(tex, uv + vec2(step.x, step.y)).a;
    float b = texture2D(tex, uv + vec2(0.0, step.y)).a;
    float bl = texture2D(tex, uv + vec2(-step.x, step.y)).a;
    float l = texture2D(tex, uv + vec2(-step.x, 0.0)).a;
    
    // Detect edges by calculating max alpha difference
    return max(
        max(max(abs(center - tl), abs(center - t)), max(abs(center - tr), abs(center - r))),
        max(max(abs(center - br), abs(center - b)), max(abs(center - bl), abs(center - l)))
    );
}

void main() {
    // Sample textures
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
    
    // Initialize with base color
    gl_FragColor = baseColor;
    
    // Calculate step size for edge detection
    vec2 step = 1.0 / u_Resolution;
    
    // Detect edges
    float edge = detectEdge(u_Tex0, v_TexCoord, step);
    
    // Pulse animation
    float pulse = 0.8 + sin(u_Time * pulseSpeed) * 0.2;
    
    // Get neon color (cycling over time)
    vec3 color = getNeonColor(u_Time * 0.1);
    
    // Apply neon effect to entire sprite
    
    // 1. Strong edge glow
    if (edge > edgeThreshold) {
        float edgeMask = smoothstep(edgeThreshold, edgeThreshold + 0.1, edge);
        gl_FragColor.rgb = mix(gl_FragColor.rgb, color, edgeMask * glowIntensity * pulse);
    }
    
    // 2. Subtle inner glow
    float innerGlow = smoothstep(0.0, 0.5, baseColor.a) * innerGlowStrength;
    gl_FragColor.rgb = mix(gl_FragColor.rgb, gl_FragColor.rgb + color * 0.3, innerGlow * pulse);
    
    // Add flickering effect
    float flicker = 0.95 + sin(u_Time * 30.0) * 0.05;
    gl_FragColor.rgb *= flicker;
} 