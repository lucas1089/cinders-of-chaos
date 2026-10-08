uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
  gl_FragColor = texture2D(u_Tex0, v_TexCoord);
  vec2 uv = v_TexCoord.xy;
  vec4 c = texture2D(u_Tex0, uv);
  
  c += texture2D(u_Tex0, uv+0.001);
  c += texture2D(u_Tex0, uv+0.003);
  c += texture2D(u_Tex0, uv+0.005);
  c += texture2D(u_Tex0, uv+0.007);
  c += texture2D(u_Tex0, uv+0.009);
  c += texture2D(u_Tex0, uv+0.011);

  c += texture2D(u_Tex0, uv-0.001);
  c += texture2D(u_Tex0, uv-0.003);
  c += texture2D(u_Tex0, uv-0.005);
  c += texture2D(u_Tex0, uv-0.007);
  c += texture2D(u_Tex0, uv-0.009);
  c += texture2D(u_Tex0, uv-0.011);

  c.rgb = vec3((c.r+c.g+c.b)/3.0);
  c = c / 7.0;
  gl_FragColor *= c;
}
