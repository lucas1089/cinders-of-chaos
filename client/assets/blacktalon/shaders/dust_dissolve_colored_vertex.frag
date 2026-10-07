#ifdef GL_ES
precision mediump float;
#endif

attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;

uniform mat3 u_TextureMatrix;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;

// Deslocamento ate a MASCARA de cores do outfit (head/body/legs/feet). O engine
// o define em DrawQueueItemOutfitWithShader::draw (g_painter->setOffset).
uniform vec2 u_Offset;

varying vec2 v_TexCoord;
// Mesmo sprite, amostrado no bloco da mascara: e ele que diz a que parte do
// corpo cada pixel pertence.
varying vec2 v_TexCoord2;

void main()
{
  gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
  v_TexCoord  = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
  v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
}
