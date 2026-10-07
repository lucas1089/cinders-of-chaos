attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform float u_Time;

// Drunk movement parameters - stronger for map
float drunkWaveSpeed = 0.8;
float drunkWaveIntensity = 0.01;

void main() {
    // Calculate position
    vec3 position = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Calculate drunk wobble
    float waveX = sin(u_Time * drunkWaveSpeed + position.y * 0.05) * drunkWaveIntensity;
    float waveY = cos(u_Time * drunkWaveSpeed * 0.7 + position.x * 0.04) * drunkWaveIntensity * 0.7;
    
    // Add secondary wobble for more drunk effect
    waveX += sin(u_Time * drunkWaveSpeed * 0.6 + position.y * 0.02) * drunkWaveIntensity * 0.5;
    waveY += cos(u_Time * drunkWaveSpeed * 0.5 + position.x * 0.03) * drunkWaveIntensity * 0.3;
    
    // Apply drunk wobble to position
    position.x += waveX * position.x;
    position.y += waveY * position.y;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Set texture coordinates with drunk wobble
    vec2 texCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    texCoord += vec2(
        sin(u_Time * 0.7 + texCoord.y * 4.0) * 0.007,
        cos(u_Time * 0.5 + texCoord.x * 3.0) * 0.005
    );
    v_TexCoord = texCoord;
} 