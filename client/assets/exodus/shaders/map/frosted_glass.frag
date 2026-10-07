uniform float u_Time;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;

uniform vec2 u_Resolution;

uniform float vx_offset;
float PixelX=2.;
float PixelY=2.;
float Freq=.915;
uniform float rt_w;// GeeXLab built-in
uniform float rt_h;// GeeXLab built-in

vec4 spline(float x,vec4 c1,vec4 c2,vec4 c3,vec4 c4,\
vec4 c5,vec4 c6,vec4 c7,vec4 c8,vec4 c9)
{
  float w1,w2,w3,w4,w5,w6,w7,w8,w9;
  w1=0.;
  w2=0.;
  w3=0.;
  w4=0.;
  w5=0.;
  w6=0.;
  w7=0.;
  w8=0.;
  w9=0.;
  float tmp=x*8.;
  if(tmp<=1.){
    w1=1.-tmp;
    w2=tmp;
  }
  else if(tmp<=2.){
    tmp=tmp-1.;
    w2=1.-tmp;
    w3=tmp;
  }
  else if(tmp<=3.){
    tmp=tmp-2.;
    w3=1.-tmp;
    w4=tmp;
  }
  else if(tmp<=4.){
    tmp=tmp-3.;
    w4=1.-tmp;
    w5=tmp;
  }
  else if(tmp<=5.){
    tmp=tmp-4.;
    w5=1.-tmp;
    w6=tmp;
  }
  else if(tmp<=6.){
    tmp=tmp-5.;
    w6=1.-tmp;
    w7=tmp;
  }
  else if(tmp<=7.){
    tmp=tmp-6.;
    w7=1.-tmp;
    w8=tmp;
  }
  else
  {
    tmp=clamp(tmp-7.,0.,1.);
    w8=1.-tmp;
    w9=tmp;
  }
  return w1*c1+w2*c2+w3*c3+w4*c4+w5*c5+w6*c6+w7*c7+\
  w8*c8+w9*c9;
}

vec3 NOISE2D(vec2 p)
{return texture2D(u_Tex1,p).xyz;}

void main()
{
  vec2 uv=v_TexCoord.xy;
  vec3 tc=vec3(1.,0.,0.);
  
  float DeltaX=PixelX/u_Resolution.x;
  float DeltaY=PixelY/u_Resolution.y;
  vec2 ox=vec2(DeltaX,0.);
  vec2 oy=vec2(0.,DeltaY);
  vec2 PP=uv-oy;
  vec4 C00=texture2D(u_Tex0,PP-ox);
  vec4 C01=texture2D(u_Tex0,PP);
  vec4 C02=texture2D(u_Tex0,PP+ox);
  PP=uv;
  vec4 C10=texture2D(u_Tex0,PP-ox);
  vec4 C11=texture2D(u_Tex0,PP);
  vec4 C12=texture2D(u_Tex0,PP+ox);
  PP=uv+oy;
  vec4 C20=texture2D(u_Tex0,PP-ox);
  vec4 C21=texture2D(u_Tex0,PP);
  vec4 C22=texture2D(u_Tex0,PP+ox);
  
  float n=NOISE2D(Freq*uv).x;
  n=mod(n,.111111)/.111111;
  vec4 result=spline(n,C00,C01,C02,C10,C11,C12,C20,C21,C22);
  tc=result.rgb;
  
  gl_FragColor=vec4(tc,1.);
}