// Cinders of Chaos: vertex stage of the liquid ground shaders chaos_liquid_water.frag and chaos_liquid_lava.frag
// (game_visualfx, base patch 0128). A ground sprite is drawn as one quad whose corners are in screen pixels and u_Center is
// its middle, so v_Norm runs -1..1 across the tile on both axes (the same trick as chaos_map_vertex.frag). v_Texel: one
// texture pixel in texture coordinates, the size of a ripple step.
attribute vec2 a_Vertex;
attribute vec2 a_TexCoord;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform mat3 u_TextureMatrix;
uniform vec2 u_Center;
varying vec2 v_TexCoord;
varying vec2 v_Norm;
varying vec2 v_Texel;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    vec2 d = a_Vertex - u_Center;
    v_Norm = d / max(abs(d), vec2(1.0));
    v_Texel = (u_TextureMatrix * vec3(1.0, 1.0, 0.0)).xy;
}
