uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;

void main()
{
  vec3 offset=vec3(0.,1.3846153846,3.2307692308);
  vec3 weight=vec3(.2270270270,.3162162162,.0702702703);
  
  vec2 uv=v_TexCoord.xy;
  vec3 tc=texture2D(u_Tex0,uv).rgb*weight[0];
  
  tc+=texture2D(u_Tex0,uv+vec2(offset.x)/u_Resolution.x,0.).rgb\
  *weight.x;
  tc+=texture2D(u_Tex0,uv-vec2(offset.x)/u_Resolution.x,0.).rgb\
  *weight.x;
  
  tc+=texture2D(u_Tex0,uv+vec2(offset.y)/u_Resolution.x,0.).rgb\
  *weight.y;
  tc+=texture2D(u_Tex0,uv-vec2(offset.y)/u_Resolution.x,0.).rgb\
  *weight.y;
  
  tc+=texture2D(u_Tex0,uv+vec2(offset.z)/u_Resolution.x,0.).rgb\
  *weight.z;
  tc+=texture2D(u_Tex0,uv-vec2(offset.z)/u_Resolution.x,0.).rgb\
  *weight.z;
  
  gl_FragColor=vec4(tc,1.);
  
}
