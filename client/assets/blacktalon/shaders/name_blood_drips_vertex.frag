// Name Blood Drips Vertex - trivial pass-through for the procedural blood-drip
// canvas drawn BELOW a name. a_TexCoord spans 0..1 across the quad and is handed
// straight to the fragment (no texture matrix), so the fragment can work in
// normalized/pixel space via u_WidgetSize.
// BlackTalon MMORPG.

attribute vec2 a_Vertex;
attribute vec2 a_TexCoord;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;

varying vec2 v_TexCoord;

void main()
{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = a_TexCoord;
}
