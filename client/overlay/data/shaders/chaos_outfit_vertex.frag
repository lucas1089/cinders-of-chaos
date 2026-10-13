// Cinders of Chaos: vertex stage of the Chaos outfit shaders (chaos_outfit_*.frag, game_chaosshaders).
// v_TexCoord: the outfit's own pixel; v_TexCoord2: the same pixel of its colour template layer (u_Offset);
// v_Px: the pixel in texture pixels (noise is laid out in sprite pixels, so it keeps its size at any zoom);
// v_Texel: one texture pixel in texture coordinates (the rim samples its neighbours).
attribute vec2 a_Vertex;
attribute vec2 a_TexCoord;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform mat3 u_TextureMatrix;
uniform vec2 u_Offset;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_Px;
varying vec2 v_Texel;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    v_Px = a_TexCoord;
    v_Texel = (u_TextureMatrix * vec3(1.0, 1.0, 0.0)).xy;
}
