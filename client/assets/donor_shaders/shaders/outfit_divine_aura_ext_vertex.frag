// Divine Aura (EXTENDED) vertex. In the extended/"AtTheEnd" path the already-
// colored outfit is composited into a padded framebuffer (25px margin all round)
// and THIS shader runs over that whole framebuffer. So v_TexCoord is simply the
// framebuffer coord (0..1 over character + margin) - body-local, continuous, and
// with room to draw the aura beyond the sprite. No u_Center needed here.
// donor client MMORPG

attribute vec2 a_Vertex;
attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;

varying vec2 v_TexCoord;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
}
