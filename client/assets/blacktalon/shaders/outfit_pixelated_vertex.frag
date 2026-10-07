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

// Helper function for rotation
vec2 rotate(vec2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    mat2 m = mat2(c, -s, s, c);
    return m * v;
}

void main() {
    // Calculate position with minimal pixel jitter
    float jitterAmount = 0.001; // Reduced jitter amount
    float jitterX = floor(sin(u_Time * 2.0 + a_Vertex.x * 5.0) * 2.0) * jitterAmount;
    float jitterY = floor(cos(u_Time * 1.5 + a_Vertex.y * 5.0) * 2.0) * jitterAmount;
    
    // Apply transform normally but with tiny jitter
    vec3 jitteredPos = vec3(a_Vertex.x + jitterX, a_Vertex.y + jitterY, 1.0);
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * jitteredPos).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates
    v_TexCoord3 = v_TexCoord;
} 