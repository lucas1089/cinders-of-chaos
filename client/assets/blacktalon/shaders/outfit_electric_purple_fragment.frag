uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying float v_ElectricIntensity;
varying vec2 v_ElectricDirection;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Electric parameters
float zapSpeed = 1.0;
float zapIntensity = 0.7;
float boltWidth = 0.03;
float glowIntensity = 0.5;

// Purple electric color function
vec3 electricColor(float t) {
    // Purple electric color palette
    vec3 darkPurple = vec3(0.4, 0.0, 0.5);
    vec3 brightPurple = vec3(0.7, 0.0, 1.0);
    vec3 magenta = vec3(1.0, 0.0, 0.8);
    vec3 pink = vec3(1.0, 0.4, 0.9);
    
    t = fract(t); // Ensure t is 0 to 1
    
    if (t < 0.33) {
        return mix(darkPurple, brightPurple, t * 3.0);
    } else if (t < 0.66) {
        return mix(brightPurple, magenta, (t - 0.33) * 3.0);
    } else {
        return mix(magenta, pink, (t - 0.66) * 3.0);
    }
}

// Lightning bolt function
float lightning(vec2 uv, float time) {
    // Create lightning bolt pattern
    float bolt = 0.0;
    
    // Main lightning path
    float path = sin(uv.x * 8.0 + time * 5.0) * 0.25;
    float dist = abs(uv.y - path);
    bolt += smoothstep(boltWidth, 0.0, dist);
    
    // Secondary branching
    for (int i = 0; i < 3; i++) {
        float branch = sin(uv.x * 10.0 + float(i) * 4.0 + time * 6.0) * 0.15;
        float branchStart = 0.3 + float(i) * 0.2;
        if (uv.x > branchStart && uv.x < branchStart + 0.3) {
            float branchDist = abs(uv.y - (path + branch));
            bolt += smoothstep(boltWidth * 0.7, 0.0, branchDist) * 0.7;
        }
    }
    
    // Add electric noise
    float noise = sin(uv.x * 100.0 + time * 20.0) * sin(uv.y * 100.0 + time * 15.0);
    bolt += noise * 0.05;
    
    return bolt;
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
        // Get normalized uv coordinates
        vec2 uv = v_TexCoord;
        
        // Create electric effect
        float bolt = lightning(uv, u_Time * zapSpeed);
        
        // Create electric glow
        float glow = sin(u_Time * 3.0) * 0.1 + 0.2;
        
        // Apply electric color
        vec3 zapColor = electricColor(u_Time * 0.3);
        
        // Mix with base color
        gl_FragColor.rgb = mix(baseColor.rgb, zapColor, bolt * zapIntensity);
        
        // Add glow
        gl_FragColor.rgb += zapColor * glow * glowIntensity;
        
        // Add electric sparkle
        float sparkle = sin(uv.x * 120.0 + uv.y * 80.0 + u_Time * 15.0) * 0.5 + 0.5;
        sparkle = pow(sparkle, 10.0) * bolt;
        gl_FragColor.rgb += vec3(1.0) * sparkle * 0.5;
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 