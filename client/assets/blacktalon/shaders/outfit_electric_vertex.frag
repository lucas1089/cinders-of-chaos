attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying float v_ElectricIntensity;
varying vec2 v_ElectricDirection;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform float u_Time;

// Electric flow parameters
vec2 electroField = vec2(466.0, 342.0);
float electricSpeed = 2.0;
float electricPhase = 0.0;

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
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Calculate electric flow direction (changes over time)
    vec2 flowDir = vec2(sin(u_Time * 0.5), cos(u_Time * 0.7));
    v_ElectricDirection = normalize(flowDir) * 0.01;
    
    // Calculate electric intensity (pulses over time)
    v_ElectricIntensity = 0.5 + sin(u_Time * 1.5) * 0.3;
    
    // Calculate moving texture coordinates for the electric effect
    v_TexCoord3 = v_TexCoord + v_ElectricDirection * u_Time * electricSpeed;
} 