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

// Stars texture parameters
vec2 starsTextureSize = vec2(221.0, 212.0);
vec2 starsDirection = vec2(1.0, 1.0);
float starsSpeed = 10.0;

// Overtexture parameters
vec2 overtextureSize = vec2(675.0, 338.0);
vec2 overtextureDirection = vec2(0.7, 0.7);
float overtextureSpeed = 8.0;
float overtextureDistortionAmount = 0.02;

void main()
{
    // Calculate stars offset with more dynamic movement
    vec2 starsOffset = starsDirection * starsSpeed * u_Time;
    starsOffset.x += sin(u_Time * 1.3) * 0.5;
    starsOffset.y += cos(u_Time * 1.1) * 0.5;
    
    // Calculate overtexture offset with distortion
    vec2 distortion = vec2(
        sin(u_Time * 1.5) * overtextureDistortionAmount,
        cos(u_Time * 1.2) * overtextureDistortionAmount
    );
    vec2 overtextureOffset = (overtextureDirection * overtextureSpeed * u_Time) + distortion;
    
    // Apply the transformations
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    
    // Pass texture coordinates to fragment shader
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    v_TexCoord3 = fract((a_TexCoord + starsOffset) / starsTextureSize); // Use fract to wrap
    v_TexCoord4 = fract((a_TexCoord + overtextureOffset) / overtextureSize); // Use fract to wrap
    
    // Pass vertex color to fragment shader
    v_Color = a_Color;
} 