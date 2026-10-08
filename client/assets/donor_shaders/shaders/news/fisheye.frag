uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  vec2 texCoord = v_TexCoord;
  vec2 center = vec2(0.5, 0.5);

  vec2 delta = texCoord - center;
  float distance = length(delta);
  vec2 direction = normalize(delta);

  float distortion = distance * distance;
  vec2 fisheyeCoord = center + direction * distortion;
  vec4 col = texture2D(u_Tex0, fisheyeCoord);
  gl_FragColor = col;
}
