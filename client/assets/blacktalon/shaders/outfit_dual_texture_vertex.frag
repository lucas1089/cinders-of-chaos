attribute vec2 a_TexCoord;
attribute vec4 a_Color;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
varying vec4 v_Color;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform float u_Time;

// Texture 1 parameters
vec2 texture1Size = vec2(675.0, 338.0);
vec2 texture1Direction = vec2(0.7, 0.8);
float texture1Speed = 8.0;

// Texture 2 parameters
vec2 texture2Size = vec2(675.0, 338.0);
vec2 texture2Direction = vec2(-0.5, 0.6);
float texture2Speed = 12.0;

void main()
{
    // Calculate texture 1 coordinates with movement
    vec2 offset1 = texture1Direction * texture1Speed * u_Time;
    offset1.x += sin(u_Time * 1.1) * 0.4;
    offset1.y += cos(u_Time * 0.9) * 0.4;
    
    // Calculate texture 2 coordinates with different movement pattern
    vec2 offset2 = texture2Direction * texture2Speed * u_Time;
    offset2.x += sin(u_Time * 0.7) * 0.3;
    offset2.y += cos(u_Time * 1.3) * 0.3;
    
    // Apply the transformations
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    
    // Pass texture coordinates to fragment shader
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    v_TexCoord3 = fract((a_TexCoord + offset1) / texture1Size);
    v_TexCoord4 = fract((a_TexCoord + offset2) / texture2Size);
    
    // Pass vertex color to fragment shader
    v_Color = a_Color;
} 