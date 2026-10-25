// Cinders of Chaos: vertex stage of the map shader chaos_map_grade (game_visualfx).
// The game map's picture is drawn as one quad whose corners are in screen pixels and u_Center is the middle of that quad
// (DrawQueue map shader, graphicalapplication.cpp). v_Norm: -1..1 across the quad on both axes (0, 0 in the middle), the
// frame of the vignette; v_TexCoord: the picture's own texture coordinate.
attribute vec2 a_Vertex;
attribute vec2 a_TexCoord;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform mat3 u_TextureMatrix;
uniform vec2 u_Center;
varying vec2 v_TexCoord;
varying vec2 v_Norm;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    vec2 d = a_Vertex - u_Center;
    v_Norm = d / max(abs(d), vec2(1.0));
}
