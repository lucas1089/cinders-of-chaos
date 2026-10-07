// Dark/Discord Boost (outfit) vertex - exposes a BODY-CENTERED position
// (v_LocalPos = a_Vertex - u_Center), the same trick the outfit_circle shaders
// use. This coordinate is:
//   - continuous across the outfit's sprite tiles (no per-tile seam), and
//   - attached to the creature: it walks WITH the body, so the effect doesn't
//     slide/jump across the screen when the character moves.
// u_Center is the creature center, set per-draw via setCenter() in outfit.cpp.
// BlackTalon MMORPG

attribute vec2 a_Vertex;
attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;

varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_LocalPos;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord  = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy; // color mask lookup
    v_LocalPos  = a_Vertex.xy - u_Center; // body-centered pixels (attached to the creature)
}
