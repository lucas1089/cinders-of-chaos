uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  vec4 col = texture2D(u_Tex0, v_TexCoord);

  float red = 1.0 * col.x + 0.0 * col.y + 0.0 * col.z;
  float green = 0.494207 * col.x + 0.0 * col.y + 1.24827 * col.z;
  float blue = 0.0 * col.x + 0.0 * col.y + 1.0 * col.z;

  col = vec4(red, green, blue, col.w);

  gl_FragColor = col;
}