uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_MovementDir;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Shadow cloak parameters
float shadowDarkness = 0.7;    // How dark the outfit becomes
float trailLength = 0.04;      // Length of the shadow trail
float trailFade = 4.0;         // How quickly the trail fades out
float shadowPulse = 0.2;       // Pulsating shadow effect intensity
float pulseSpeed = 0.8;        // Speed of pulsation

// Smoke/shadow effect parameters
float smokeAmount = 0.3;       // Amount of smoke/shadow particles
float smokeSpeed = 0.5;        // Speed of smoke movement
float smokeTurbulence = 2.0;   // Turbulence of smoke
float smokeDensity = 0.7;      // Density of smoke effect

// Simple noise function
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Fractal noise for smoke-like effect
float fractalNoise(vec2 p) {
    float f = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    
    for (int i = 0; i < 4; i++) {
        f += amp * noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    
    return f;
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
    
    // Initialize with base (darkened) color
    vec4 resultColor = baseColor;
    
    // Darken the outfit
    float darkness = shadowDarkness;
    
    // Add subtle pulsating effect to darkness
    darkness += sin(u_Time * pulseSpeed) * shadowPulse;
    
    // Apply darkening
    resultColor.rgb *= (1.0 - darkness);
    
    // Calculate shadow trail direction based on movement
    vec2 trailDir = normalize(v_MovementDir) * trailLength;
    
    // Sample multiple points along the trail
    vec4 trailColor = vec4(0.0, 0.0, 0.0, 0.0);
    
    // Create shadow trail by sampling behind the character
    for (int i = 1; i <= 5; i++) {
        float trailStep = float(i) / 5.0;
        vec2 trailUV = v_TexCoord - trailDir * trailStep;
        vec4 sampleColor = texture2D(u_Tex0, trailUV);
        
        // Only add to trail if pixel has alpha (is part of the character)
        if (sampleColor.a > 0.1) {
            // Fade out the trail as it gets further from character
            float fadeFactor = exp(-trailStep * trailFade);
            trailColor.a += sampleColor.a * fadeFactor * 0.15;
        }
    }
    
    // Create shadow smoke effect with noise
    // Generate time-varying smoke-like texture
    vec2 smokeUV = v_TexCoord3 * smokeTurbulence;
    smokeUV.y += u_Time * smokeSpeed;
    
    float smoke = fractalNoise(smokeUV);
    
    // Only show smoke around the edges of the character
    float edgeFactor = 1.0 - smoothstep(0.2, 0.8, baseColor.a);
    
    // Add the smoke effect
    float smokeStrength = smoke * smokeAmount * edgeFactor;
    
    // Combine shadow effects with the base darkened color
    resultColor.rgb = mix(resultColor.rgb, vec3(0.0, 0.0, 0.0), smokeStrength * smokeDensity);
    
    // Add the trail shadow
    resultColor.rgb = mix(resultColor.rgb, vec3(0.0, 0.0, 0.0), trailColor.a);
    
    // Final output
    gl_FragColor = resultColor;
} 