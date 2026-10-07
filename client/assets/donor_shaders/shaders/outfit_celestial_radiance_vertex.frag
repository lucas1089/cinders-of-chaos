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

// Celestial parameters
float celestialWaveIntensity = 0.001; // Very subtle wave effect

void main() {
    // Get original vertex position
    vec3 originalPos = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Apply a subtle celestial wave effect
    vec2 modifiedPos = originalPos.xy;
    float celestialWave = sin(u_Time * 0.3 + originalPos.x * 0.02 + originalPos.y * 0.03);
    modifiedPos += vec2(celestialWave, celestialWave) * celestialWaveIntensity;
    
    // Calculate final position 
    gl_Position = vec4((u_ProjectionMatrix * vec3(modifiedPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized texture coordinates to fragment shader
    v_TexCoord3 = a_TexCoord;
} 