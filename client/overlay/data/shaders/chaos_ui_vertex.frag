// Cinders of Chaos: vertex stage of the UI widget shaders (chaos_ui_*.frag; base patch 0044, game_shaderfx).
// v_TexCoord: the image's texture coordinates, 0..1 over a widget image that is a whole picture.
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
