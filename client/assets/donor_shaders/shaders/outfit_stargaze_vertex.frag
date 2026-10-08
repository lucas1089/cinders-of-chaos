attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;
uniform float u_Time;

// Flow parameters
varying float v_FlowIntensity;
varying vec2 v_FlowDirection;
varying float v_CosmicPhase;
varying float v_OrbPhase;
varying float v_DistanceFromCenter;
varying float v_ExplosionPhase;

// Orb parameters
float orbCount = 12.0;
float orbRadius = 0.15;

// Explosion parameters
float explosionCount = 5.0;
float explosionSpeed = 2.0;
float explosionRadius = 0.3;

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

void main()
{
    // Calculate distance from center for orb effect
    v_DistanceFromCenter = length(a_Vertex - u_Center);
    
    // Create flowing effect with orb movement
    v_FlowIntensity = sin(u_Time * 0.8) * 0.2 + 0.8;
    
    // Calculate direction towards center for orb movement
    vec2 toCenter = normalize(u_Center - a_Vertex);
    v_FlowDirection = toCenter * 0.3;
    
    // Calculate cosmic phase for color transitions
    v_CosmicPhase = mod(u_Time * 0.3, 1.0);
    
    // Calculate orb phase for individual orb movement
    v_OrbPhase = mod(u_Time * 0.5, 1.0);
    
    // Calculate explosion phase
    v_ExplosionPhase = mod(u_Time * explosionSpeed, 1.0);
    
    // Apply the transformations
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    
    // Calculate normalized texture coordinates
    vec2 normalizedTexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord = normalizedTexCoord;
    v_TexCoord2 = normalizedTexCoord + u_Offset;
    
    // Calculate orb positions and movement
    vec2 orbOffset = vec2(0.0);
    for(float i = 0.0; i < orbCount; i += 1.0) {
        // Get base position for this orb
        vec2 basePos = scatteredPosition(i);
        
        // Add random movement
        vec2 randomMove = randomMovement(i, u_Time);
        
        // Calculate phase for expansion/contraction
        float phase = mod(u_Time * (0.5 + sin(i * 2.0) * 0.3), 1.0);
        float expansion = smoothstep(0.0, 0.3, phase) * (1.0 - smoothstep(0.7, 1.0, phase));
        
        // Combine all movements
        vec2 orbPos = basePos + randomMove;
        orbPos *= expansion;
        
        // Add chaotic movement for certain orbs
        if (mod(i, 3.0) < 0.1) {
            float chaos = sin(u_Time * 3.0 + i) * 0.1;
            orbPos += vec2(
                sin(u_Time * 5.0 + i) * chaos,
                cos(u_Time * 4.0 + i) * chaos
            );
        }
        
        orbOffset += orbPos;
    }
    
    // Calculate explosion effects
    vec2 explosionOffset = vec2(0.0);
    for(float i = 0.0; i < explosionCount; i += 1.0) {
        // Get explosion position
        vec2 expPos = explosionPosition(i);
        
        // Calculate explosion phase
        float expPhase = mod(u_Time * explosionSpeed + i * 0.2, 1.0);
        float expStrength = smoothstep(0.0, 0.3, expPhase) * (1.0 - smoothstep(0.7, 1.0, expPhase));
        
        // Add random direction to explosion
        vec2 expDir = normalize(vec2(sin(i * 10.0), cos(i * 8.0)));
        expPos += expDir * expStrength * explosionRadius;
        
        explosionOffset += expPos;
    }
    
    // Calculate texture offsets with orb and explosion effects
    // Scale the effects based on texture size
    vec2 starsOffset = orbOffset * 0.5 + explosionOffset * 0.3;
    vec2 overtextureOffset = orbOffset * 0.3 + explosionOffset * 0.2;
    
    // Pass texture coordinates to fragment shader with proper scaling
    v_TexCoord3 = normalizedTexCoord + starsOffset;
    v_TexCoord4 = normalizedTexCoord + overtextureOffset;
} 