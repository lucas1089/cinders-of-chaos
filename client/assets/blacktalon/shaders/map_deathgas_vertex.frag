attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;

varying vec2 v_TexCoord;
varying vec2 v_WorldPos;

uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;

uniform float u_Time;

void main()
{
    // Calculate position
    vec3 position = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Pass world position to fragment shader for effect calculation
    v_WorldPos = position.xy;
    
    // Calculate distance from advancing gas front
    float wavePosition = 20.0 * u_Time; // Same as WAVE_SPEED in fragment shader
    float distanceFromFront = wavePosition - position.y;
    
    // Apply stronger distortion near the front of the gas
    float frontDistortion = max(0.0, 20.0 - abs(distanceFromFront)) / 20.0;
    
    // Basic distortion that increases with time for areas inside the gas
    float inGasDistortion = smoothstep(-20.0, 0.0, distanceFromFront) * 0.7;
    
    // Combined distortion effect
    float distortionAmount = frontDistortion * 2.0 + inGasDistortion;
    
    // Apply wave-like distortion
    float heatWave = sin(position.y * 0.04 + u_Time * 1.2) * sin(position.x * 0.03 + u_Time) * distortionAmount;
    position.x += heatWave;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Apply heat distortion to texture coordinates as well
    vec2 texCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Add more wave-like distortion to texture coordinates based on time and distance from front
    float texDistortion = sin(texCoord.y * 8.0 + u_Time * 1.5) * 0.002 * distortionAmount;
    texCoord.x += texDistortion;
    
    v_TexCoord = texCoord;
} 