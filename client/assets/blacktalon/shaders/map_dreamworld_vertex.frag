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
    
    // No distortion in vertex shader - prevents jumping
    // All dreamworld effects will be handled in the fragment shader
    
    // Calculate final position without any distortion
    gl_Position = vec4((u_ProjectionMatrix * position).xy, 1.0, 1.0);
    
    // Use standard texture coordinates without any distortion
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
} 