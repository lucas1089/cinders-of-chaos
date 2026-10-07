attribute vec2 a_TexCoord;
attribute vec4 a_Color;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec4 v_Color;
varying vec2 v_Position;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Resolution;
uniform vec2 u_Center;
uniform float u_Time;

// Texture parameters
vec2 effectTextureSize = vec2(675.0, 338.0);
vec2 direction = vec2(0.8, 0.6);
float speed = 12.0;
float noiseSpeed = 5.0;

void main()
{
    // Calculate offset with subtle movement
    vec2 offset = direction * speed * u_Time;
    
    // Add some wobble to the movement
    offset.x += sin(u_Time * 1.5) * 0.3;
    offset.y += cos(u_Time * 1.2) * 0.3;
    
    // Pass position for noise generation
    v_Position = a_Vertex.xy;
    
    // Apply the transformations
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    
    // Pass texture coordinates to fragment shader
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    v_TexCoord3 = fract((a_TexCoord + offset) / effectTextureSize);
    
    // Pass vertex color to fragment shader
    v_Color = a_Color;
} 