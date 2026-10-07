// Name Sweep Vertex - like name_vertex, but ALSO exposes the text-local vertex
// position (v_LocalPos) so a fragment can do a screen-consistent VERTICAL sweep
// across the whole text block. v_TexCoord alone is the per-glyph font-atlas
// coordinate (each letter lives at a different atlas row), so it cannot drive a
// uniform directional sweep - v_LocalPos can (a_Vertex is text-local pixels:
// y = 0 at the top of the line, ~lineHeight at the bottom, shared by all glyphs).
// Dedicated to the "Divine" text shader; the other name shaders keep name_vertex.

attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;

varying vec2 v_TexCoord;
varying vec2 v_LocalPos;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy + u_Offset, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_LocalPos = a_Vertex.xy; // text-local pixels (0..lineHeight), consistent across glyphs
}
