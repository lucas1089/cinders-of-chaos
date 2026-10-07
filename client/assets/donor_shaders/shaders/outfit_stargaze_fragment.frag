uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
varying float v_FlowIntensity;
varying vec2 v_FlowDirection;
varying float v_CosmicPhase;
varying float v_OrbPhase;
varying float v_DistanceFromCenter;
varying float v_ExplosionPhase;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform vec2 u_Resolution;
uniform float u_Time;

// Effect parameters
float flowSpeed = 0.6;
float flowIntensity = 0.8;
float cosmicIntensity = 1.0;
float orbIntensity = 1.2;
float cloudIntensity = 0.8;
float explosionIntensity = 1.5;

// Orb parameters
float orbCount = 12.0;
float orbRadius = 0.15;

// Explosion parameters
float explosionCount = 5.0;
float explosionSpeed = 2.0;
float explosionRadius = 0.3;
float pixelSize = 0.02;

// Cosmic color palette function
vec3 cosmicPalette(float t) {
    // Cosmic color palette
    vec3 purple = vec3(0.8, 0.2, 1.0);
    vec3 magenta = vec3(1.0, 0.2, 0.8);
    vec3 aqua = vec3(0.2, 0.8, 1.0);
    vec3 blue = vec3(0.2, 0.4, 1.0);
    vec3 yellow = vec3(1.0, 1.0, 0.2);
    vec3 green = vec3(0.2, 1.0, 0.4);
    
    // Oscillate through cosmic colors
    t = fract(t);
    
    if (t < 0.166) {
        return mix(purple, magenta, t * 6.0);
    } else if (t < 0.333) {
        return mix(magenta, aqua, (t - 0.166) * 6.0);
    } else if (t < 0.5) {
        return mix(aqua, blue, (t - 0.333) * 6.0);
    } else if (t < 0.666) {
        return mix(blue, yellow, (t - 0.5) * 6.0);
    } else if (t < 0.833) {
        return mix(yellow, green, (t - 0.666) * 6.0);
    } else {
        return mix(green, purple, (t - 0.833) * 6.0);
    }
}

// Random movement function
vec2 randomMovement(float seed, float time) {
    float speed = 0.5 + sin(seed * 10.0) * 0.3;
    float angle = seed * 6.28318 + time * speed;
    float radius = 0.3 + sin(seed * 5.0) * 0.1;
    
    return vec2(
        cos(angle) * radius,
        sin(angle) * radius
    );
}

// Scattered position function
vec2 scatteredPosition(float index) {
    float angle = (index / orbCount) * 6.28318;
    float radius = 0.4 + sin(index * 3.0) * 0.1;
    
    return vec2(
        cos(angle) * radius,
        sin(angle) * radius
    );
}

// Explosion position function
vec2 explosionPosition(float index) {
    float angle = (index / explosionCount) * 6.28318;
    float radius = 0.2 + sin(index * 5.0) * 0.1;
    
    return vec2(
        cos(angle) * radius,
        sin(angle) * radius
    );
}

// Orb effect function
float orbEffect(vec2 uv, float time, float index) {
    // Get base position for this orb
    vec2 basePos = scatteredPosition(index);
    
    // Add random movement
    vec2 randomMove = randomMovement(index, time);
    
    // Calculate phase for expansion/contraction
    float phase = mod(time * (0.5 + sin(index * 2.0) * 0.3), 1.0);
    float expansion = smoothstep(0.0, 0.3, phase) * (1.0 - smoothstep(0.7, 1.0, phase));
    
    // Combine all movements
    vec2 orbPos = basePos + randomMove;
    orbPos *= expansion;
    
    // Add chaotic movement for certain orbs
    if (mod(index, 3.0) < 0.1) {
        float chaos = sin(time * 3.0 + index) * 0.1;
        orbPos += vec2(
            sin(time * 5.0 + index) * chaos,
            cos(time * 4.0 + index) * chaos
        );
    }
    
    // Calculate distance to orb center
    float dist = length(uv - orbPos);
    
    // Create orb with soft edges
    float orb = smoothstep(orbRadius * 0.5, 0.0, dist);
    
    // Add cloudy effect inside orb
    float cloud = sin(dist * 20.0 + time * 2.0) * 0.5 + 0.5;
    cloud *= smoothstep(0.0, orbRadius * 0.3, orbRadius * 0.5 - dist);
    
    // Add speed trails for fast-moving orbs
    float speedTrail = 0.0;
    if (mod(index, 3.0) < 0.1) {
        speedTrail = sin(dist * 30.0 - time * 10.0) * 0.5 + 0.5;
        speedTrail *= smoothstep(0.0, orbRadius * 0.2, orbRadius * 0.4 - dist);
    }
    
    return orb + cloud * 0.5 + speedTrail * 0.3;
}

// Pixel explosion effect function
float pixelExplosion(vec2 uv, float time, float index) {
    // Get explosion position
    vec2 expPos = explosionPosition(index);
    
    // Calculate explosion phase
    float expPhase = mod(time * explosionSpeed + index * 0.2, 1.0);
    float expStrength = smoothstep(0.0, 0.3, expPhase) * (1.0 - smoothstep(0.7, 1.0, expPhase));
    
    // Add random direction to explosion
    vec2 expDir = normalize(vec2(sin(index * 10.0), cos(index * 8.0)));
    expPos += expDir * expStrength * explosionRadius;
    
    // Calculate distance to explosion center
    float dist = length(uv - expPos);
    
    // Create pixelated explosion with dynamic grid size
    float gridSize = 50.0 * (1.0 + expStrength * 2.0);
    float pixelGrid = fract(uv.x * gridSize) * fract(uv.y * gridSize);
    float explosion = smoothstep(explosionRadius * 0.5, 0.0, dist);
    explosion *= pixelGrid * expStrength;
    
    // Add sparkle effect
    float sparkle = sin(dist * 100.0 + time * 10.0) * 0.5 + 0.5;
    sparkle *= smoothstep(0.0, explosionRadius * 0.2, explosionRadius * 0.3 - dist);
    
    return explosion + sparkle * 0.5;
}

void main() {
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 starsEffect = texture2D(u_Tex1, v_TexCoord3);
    vec4 overtextureEffect = texture2D(u_Tex2, v_TexCoord4);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Initialize with dark backdrop
    gl_FragColor = vec4(0.0, 0.0, 0.0, baseColor.a);
    
    if(texcolor.a > 0.9) {
        // Create orb effects
        float totalOrbEffect = 0.0;
        for(float i = 0.0; i < orbCount; i += 1.0) {
            totalOrbEffect += orbEffect(v_TexCoord, u_Time, i);
        }
        
        // Apply cosmic colors to orbs
        vec3 orbColor = cosmicPalette(v_CosmicPhase);
        gl_FragColor.rgb += orbColor * totalOrbEffect * orbIntensity;
        
        // Create explosion effects
        float totalExplosionEffect = 0.0;
        for(float i = 0.0; i < explosionCount; i += 1.0) {
            totalExplosionEffect += pixelExplosion(v_TexCoord, u_Time, i);
        }
        
        // Apply cosmic colors to explosions
        vec3 explosionColor = cosmicPalette(v_ExplosionPhase);
        gl_FragColor.rgb += explosionColor * totalExplosionEffect * explosionIntensity;
        
        // Add cloudy effect between orbs
        float cloudEffect = sin(v_TexCoord.x * 30.0 + u_Time * 1.5) * 0.5 + 0.5;
        cloudEffect *= sin(v_TexCoord.y * 25.0 + u_Time * 1.2) * 0.5 + 0.5;
        cloudEffect = pow(cloudEffect, 2.0) * 0.3;
        
        // Apply cosmic colors to clouds
        vec3 cloudColor = cosmicPalette(v_CosmicPhase + 0.3);
        gl_FragColor.rgb += cloudColor * cloudEffect * cloudIntensity;
        
        // Add speed trails for fast-moving orbs
        float speedTrail = sin(v_TexCoord.x * 50.0 - u_Time * 8.0) * 0.5 + 0.5;
        speedTrail *= sin(v_TexCoord.y * 50.0 - u_Time * 6.0) * 0.5 + 0.5;
        speedTrail = pow(speedTrail, 3.0) * 0.4;
        gl_FragColor.rgb += cosmicPalette(u_Time * 0.4) * speedTrail;
        
        // Add cosmic sparkle
        float sparkle = sin(v_TexCoord.x * 100.0 + u_Time * 3.0) * 0.5 + 0.5;
        sparkle *= sin(v_TexCoord.y * 100.0 + u_Time * 2.5) * 0.5 + 0.5;
        sparkle = pow(sparkle, 8.0) * 0.4;
        gl_FragColor.rgb += cosmicPalette(u_Time * 0.2) * sparkle;
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 