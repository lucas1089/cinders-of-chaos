uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
varying vec2 v_Center;
varying float v_DistanceFromCenter;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Pseudo-random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Blessed stripe function
float blessedStripe(vec2 uv) {
    float stripeWidth = 0.1;
    float stripe = mod(uv.x + uv.y, 1.0);
    return smoothstep(0.0, stripeWidth, stripe) * smoothstep(1.0, 1.0 - stripeWidth, stripe);
}

// Ring wave function
float createRingWave(float dist, float phase, float width, float softness) {
    float wave = sin(dist * 10.0 - phase);
    return smoothstep(-softness, softness, wave) * width;
}

// Pixelated particle function
vec3 createPixelParticle(vec2 uv, float seed, float speed, float size, float alpha_edge) {
    // Create a pixelated grid
    vec2 pixelSize = vec2(size);
    vec2 pixelUV = floor(uv / pixelSize) * pixelSize;
    
    // Generate random values for this pixel
    float r = random(pixelUV + seed);
    float r2 = random(pixelUV * 2.0 + seed);
    
    // Vertical movement with slight horizontal drift
    float yOffset = mod(u_Time * speed + r * 6.28318, 1.0);
    float xOffset = sin(r2 * 6.28318 + u_Time) * 0.1;
    
    // Check if this pixel should be a particle, more likely near alpha edge
    float isParticle = step(0.97 - alpha_edge * 0.2, r);
    
    // Create particle color with pixel perfect edges
    vec3 particleColor = vec3(1.2, 1.1, 0.8) * step(0.5, r2);
    
    // Apply movement
    float yPos = mod(pixelUV.y + yOffset, 1.0);
    float xPos = mod(pixelUV.x + xOffset, 1.0);
    
    // Create sharp pixel edges
    float pixel = step(0.48, 0.5 - abs(yPos - 0.5)) * 
                 step(0.48, 0.5 - abs(xPos - 0.5)) *
                 isParticle;
    
    return particleColor * pixel;
}

void main()
{
    // Sample base texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Initialize output color
    gl_FragColor = baseColor;
    
    if(texcolor.a > 0.01) {
        // Apply outfit colors first
        if(texcolor.r > 0.9) {
            gl_FragColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
        } else if(texcolor.g > 0.9) {
            gl_FragColor *= u_Color[2];
        } else if(texcolor.b > 0.9) {
            gl_FragColor *= u_Color[3];
        }
        
        // Sample and apply holy texture with movement
        vec2 holyUV = v_TexCoord3;
        holyUV.y = fract(holyUV.y - u_Time * 0.5); // Upward movement
        vec4 holyEffect = texture2D(u_Tex1, holyUV);
        
        // Blend holy texture over the base color
        vec3 holyColor = holyEffect.rgb * vec3(1.2, 1.1, 0.9); // Slightly golden tint
        gl_FragColor.rgb = mix(gl_FragColor.rgb, holyColor, holyEffect.a * 0.7);
        
        // Calculate time for ring patterns
        float baseTime = u_Time * 2.0;
        float fastTime = u_Time * 4.0;
        
        // Create sequential rings (1,2,3,4) with reduced intensity
        float ring1 = createRingWave(v_DistanceFromCenter, baseTime, 0.3, 0.2);
        float ring2 = createRingWave(v_DistanceFromCenter, baseTime - 1.57, 0.25, 0.2);
        float ring3 = createRingWave(v_DistanceFromCenter, baseTime - 3.14, 0.2, 0.2);
        float ring4 = createRingWave(v_DistanceFromCenter, baseTime - 4.71, 0.15, 0.2);
        
        // Create burst pattern with reduced intensity
        float burstPhase = mod(fastTime, 8.0);
        float burstIntensity = step(4.0, burstPhase) * 0.3;
        
        float burstRings = 0.0;
        for(int i = 0; i < 4; i++) {
            float offset = float(i) * 0.785;
            burstRings += createRingWave(v_DistanceFromCenter, fastTime - offset, 0.15, 0.15);
        }
        
        // Combine rings
        float ringEffect = ring1 + ring2 + ring3 + ring4;
        ringEffect += burstRings * burstIntensity;
        ringEffect = min(ringEffect, 0.8); // Cap the maximum intensity
        
        // Create white-gold gradient for rings with reduced intensity
        vec3 ringColor = mix(
            vec3(1.0, 0.95, 0.7),    // Gold
            vec3(1.0, 1.0, 1.0),     // White
            sin(v_DistanceFromCenter * 5.0 + u_Time) * 0.3 + 0.5
        );
        
        // Add blessed stripes with reduced intensity
        float stripe = blessedStripe(v_TexCoord3 * 2.0) * 0.2;
        vec3 stripeColor = vec3(1.2, 1.15, 0.9) * stripe;
        
        // Add pulsing holy glow with reduced intensity
        float glowPulse = 0.1 * sin(u_Time * 2.2) + 0.1;
        
        // Combine all effects with proper blending
        vec3 effectsColor = ringColor * ringEffect * 0.4 + stripeColor;
        
        // Blend effects with current color
        gl_FragColor.rgb = mix(gl_FragColor.rgb, gl_FragColor.rgb + effectsColor, 0.7);
        gl_FragColor.rgb += gl_FragColor.rgb * glowPulse;
        
        // Add subtle color shifting
        float colorShift = sin(u_Time * 1.8) * 0.05 + 0.05;
        gl_FragColor.r += colorShift;
        gl_FragColor.g += colorShift * 0.9;
        
        // Final brightness adjustment (reduced)
        gl_FragColor.rgb *= 1.1;
    }
    
    // Allow particles to appear in semi-transparent areas
    if(gl_FragColor.a < 0.99 && gl_FragColor.a > 0.01) {
        vec3 alphaParticles = vec3(0.0);
        alphaParticles += createPixelParticle(v_TexCoord, 5.0, 2.2, 0.02, 1.0) * 2.0;
        alphaParticles += createPixelParticle(v_TexCoord, 6.0, 1.6, 0.03, 1.0) * 1.5;
        gl_FragColor.rgb += alphaParticles;
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 