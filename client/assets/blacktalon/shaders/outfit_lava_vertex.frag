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
varying float v_ExplosionPhase;
varying float v_DistanceFromCenter;

// Stars texture parameters
vec2 starsTextureSize = vec2(221.0, 212.0);
vec2 starsDirection = vec2(1.0, 1.0);
float starsSpeed = 12.0;

// Overtexture parameters
vec2 overtextureSize = vec2(675.0, 338.0);
vec2 overtextureDirection = vec2(0.7, 0.7);
float overtextureSpeed = 10.0;
float overtextureDistortionAmount = 0.03;

// Lava flow parameters
float lavaFlowSpeed = 1.5;
float lavaFlowIntensity = 0.4;

void main()
{
    // Calculate distance from center for explosion effect
    v_DistanceFromCenter = length(a_Vertex - u_Center);
    
    // Create flowing effect with lava-like movement
    v_FlowIntensity = sin(u_Time * 1.2) * 0.3 + 0.7;
    
    // Calculate direction towards center with lava-like flow
    vec2 toCenter = normalize(u_Center - a_Vertex);
    v_FlowDirection = toCenter * lavaFlowIntensity + 
        vec2(sin(u_Time * lavaFlowSpeed) * 0.2, 
             cos(u_Time * lavaFlowSpeed * 0.8) * 0.2);
    
    // Calculate cosmic phase for color transitions
    v_CosmicPhase = mod(u_Time * 0.5, 1.0);
    
    // Calculate explosion phase (every 2.5 seconds)
    v_ExplosionPhase = mod(u_Time, 2.5);
    
    // Apply the transformations
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Calculate stars offset with lava-like flow
    vec2 starsOffset = starsDirection * starsSpeed * u_Time;
    starsOffset += v_FlowDirection * 0.2;
    
    // Calculate overtexture offset with enhanced distortion
    vec2 distortion = vec2(
        sin(u_Time * 2.0) * overtextureDistortionAmount,
        cos(u_Time * 1.8) * overtextureDistortionAmount
    );
    vec2 overtextureOffset = (overtextureDirection * overtextureSpeed * u_Time) + distortion;
    overtextureOffset += v_FlowDirection * 0.3;
    
    // Calculate inverted explosion effect
    float explosionStrength = 0.0;
    if (v_ExplosionPhase < 1.0) {
        explosionStrength = smoothstep(0.0, 1.0, v_ExplosionPhase);
    } else if (v_ExplosionPhase < 2.0) {
        explosionStrength = smoothstep(1.0, 0.0, v_ExplosionPhase - 1.0);
    }
    
    // Apply explosion effect to texture coordinates with stronger inward pull
    vec2 explosionOffset = toCenter * explosionStrength * 0.15;
    
    // Pass texture coordinates to fragment shader with lava-like flow
    v_TexCoord3 = ((a_TexCoord + starsOffset) / starsTextureSize) - explosionOffset;
    v_TexCoord4 = ((a_TexCoord + overtextureOffset) / overtextureSize) - explosionOffset;
} 