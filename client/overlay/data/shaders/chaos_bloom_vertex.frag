// Cinders of Chaos: vertex stage of the soft glow shaders (chaos_bloom_*.frag; base patch 0132, game_visualfx).
// A plain textured quad: v_TexCoord is the texture coordinate of the picture being read.
attribute vec2 a_Vertex;
attribute vec2 a_TexCoord;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
}
