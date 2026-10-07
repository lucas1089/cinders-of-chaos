attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;
uniform float u_Time;

// Flow parameters
varying float v_FlowIntensity;
varying vec2 v_FlowDirection;

void main()
{
    // Create flowing effect
    v_FlowIntensity = sin(u_Time * 0.8) * 0.2 + 0.8;
    v_FlowDirection = vec2(sin(u_Time * 0.5) * 0.2, cos(u_Time * 0.7) * 0.2);
    
    // Apply the transformations
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Add subtle motion to simulate flowing
    v_TexCoord3 = v_TexCoord + vec2(sin(u_Time * 0.4 + v_TexCoord.y * 10.0) * 0.02, 
                                   cos(u_Time * 0.3 + v_TexCoord.x * 8.0) * 0.02);
} 