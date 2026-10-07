uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
void main()
{
  float time=abs(sin(u_Time));
  
  vec2 dir=vec2(.9-v_TexCoord.x,1.5-v_TexCoord.y);
  
  vec2 center=dir;
  
  // vec3 shockParams=texture2D(u_Tex0,v_TexCoord).xyz;
  vec3 shockParams=vec3(10.,.8,.1);// 10.0, 0.8, 0.1
  vec2 uv=v_TexCoord.xy;
  vec2 texCoord=uv;
  float distance=distance(uv,center);
  if((distance<=(time+shockParams.z))&&
  (distance>=(time-shockParams.z)))
  {
    float diff=(distance-time);
    float powDiff=1.-pow(abs(diff*shockParams.x),
  shockParams.y);
  float diffTime=diff*powDiff;
  vec2 diffUV=normalize(uv-center);
  texCoord=uv+(diffUV*diffTime);
}
gl_FragColor+=texture2D(u_Tex0,texCoord);

}
