uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Fire parameters
float fireSpeed = 1.5;
float fireIntensity = 0.8;
float flameHeight = 2.0;

// Noise functions for the fire effect
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 57.0;
    return mix(
        mix(hash(n), hash(n + 1.0), f.x),
        mix(hash(n + 57.0), hash(n + 58.0), f.x),
        f.y
    );
}

// FBM (Fractal Brownian Motion) for natural fire movement
float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    
    for(int i = 0; i < 4; i++) {
        sum += amp * noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
        p = vec2(p.y - sum * 0.1, p.x);
    }
    
    return sum;
}

// Fire color function
vec3 fireColor(float y) {
    // Fire color gradient - from yellow/white to orange to red to dark red/black
    vec3 yellow = vec3(1.0, 0.9, 0.3);
    vec3 orange = vec3(1.0, 0.6, 0.0);
    vec3 red = vec3(1.0, 0.2, 0.0);
    vec3 darkRed = vec3(0.5, 0.0, 0.0);
    vec3 black = vec3(0.0, 0.0, 0.0);
    
    y = clamp(y, 0.0, 1.0);
    
    if (y < 0.2) {
        return mix(black, darkRed, y * 5.0);
    } else if (y < 0.4) {
        return mix(darkRed, red, (y - 0.2) * 5.0);
    } else if (y < 0.7) {
        return mix(red, orange, (y - 0.4) * 3.33);
    } else {
        return mix(orange, yellow, (y - 0.7) * 3.33);
    }
}

void main() {
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
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
        // Create fire effect
        vec2 uv = v_TexCoord;
        
        // Invert y for flames to rise up
        float y = 1.0 - uv.y;
        
        // Animated noise for fire movement
        float time = u_Time * fireSpeed;
        float noise1 = fbm(vec2(uv.x * 4.0, (y * flameHeight - time * 1.5) * 2.0));
        float noise2 = fbm(vec2(uv.x * 2.0 - time * 0.5, (y * flameHeight + time) * 2.0));
        
        // Combine noises for realistic fire
        float fireNoise = noise1 * noise2 * y * 1.5;
        
        // Add flickering
        float flicker = noise(vec2(time * 2.0, uv.x * 10.0)) * 0.1 + 0.9;
        
        // Create fire mask with smooth falloff at edges
        float edge = smoothstep(0.0, 0.4, uv.x) * smoothstep(1.0, 0.6, uv.x);
        float fireMask = smoothstep(0.0, y * 1.2, fireNoise) * edge * flicker;
        
        // Apply fire color
        vec3 flameColor = fireColor(fireMask * y * 1.3);
        
        // Mix with base color
        gl_FragColor.rgb = mix(baseColor.rgb, flameColor, fireMask * fireIntensity);
        
        // Add glow for brighter parts
        float glow = fireMask * fireMask * 0.5;
        gl_FragColor.rgb += flameColor * glow;
        
        // Add sparks
        float sparkChance = noise(vec2(uv.x * 20.0 + time, uv.y * 20.0 - time));
        if (sparkChance > 0.97 && y > 0.3) {
            gl_FragColor.rgb = vec3(1.0, 0.9, 0.5);
        }
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 