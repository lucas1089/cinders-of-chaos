// Border glow vertex shader
// Must output v_WidgetUV as 0..1 UV coordinates for fragment shader
attribute vec2 a_Vertex;
attribute vec2 a_TexCoord;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform float u_Depth;
varying vec2 v_WidgetUV;

void main() {
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, u_Depth / 16384.0, 1.0);
    v_WidgetUV = a_TexCoord;
}
