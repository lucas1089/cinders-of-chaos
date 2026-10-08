attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Resolution;
uniform float u_Depth;

void main()
{
	gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, u_Depth / 12384.0, 1.0);
	v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
	v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
	v_TexCoord3 = (u_TextureMatrix * vec3(u_Resolution, 1.0)).xy;

}