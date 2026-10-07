attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform float u_Time;

// Drunk movement parameters
float drunkWaveSpeed = 1.5;
float drunkWaveIntensity = 0.03;

// Helper function for rotation
vec2 rotate(vec2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    mat2 m = mat2(c, -s, s, c);
    return m * v;
}

void main() {
    // Calculate position
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    
    // Calculate drunk wobble
    float waveX = sin(u_Time * drunkWaveSpeed + a_Vertex.y * 8.0) * drunkWaveIntensity;
    float waveY = cos(u_Time * drunkWaveSpeed * 0.8 + a_Vertex.x * 6.0) * drunkWaveIntensity * 0.7;
    
    // Add secondary wobble
    waveX += sin(u_Time * drunkWaveSpeed * 0.7 + a_Vertex.y * 3.0) * drunkWaveIntensity * 0.5;
    waveY += cos(u_Time * drunkWaveSpeed * 0.5 + a_Vertex.x * 4.0) * drunkWaveIntensity * 0.3;
    
    // Apply drunk wobble to vertex position
    gl_Position.x += waveX;
    gl_Position.y += waveY;
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates with drunk wobble
    v_TexCoord3 = v_TexCoord + vec2(
        sin(u_Time * 1.2 + a_TexCoord.y * 5.0) * 0.02,
        cos(u_Time * 0.9 + a_TexCoord.x * 4.0) * 0.015
    );
} 