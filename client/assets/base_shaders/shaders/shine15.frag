uniform float u_Time;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;

vec2 rotate(vec2 v,float a){
 float s=sin(a);
 float c=cos(a);
 mat2 m=mat2(c,-s,s,c);
 return m*v;
}

vec4 ShadowLight(sampler2D source,vec2 uv,float precisao,float size,vec4 color,float intensity,float posx,float posy,float fade)
{
 float samples=precisao;
 float samples2=samples*.5;
 vec4 ret=vec4(0,0,0,0);
 float count=0.;
 for(float iy=-samples2;iy<samples2;iy++)
 {
  for(float ix=-samples2;ix<samples2;ix++)
  {
   vec2 uv2=vec2(ix,iy);
   uv2/=samples;
   uv2*=size*.1;
   uv2+=vec2(-posx,posy);
   uv2=(uv+uv2);
   ret+=texture2D(source,uv2);
   count++;
  }
 }
 ret=mix(vec4(0,0,0,0),ret/count,intensity);
 ret.rgb=color.rgb;
 vec4 m=ret;
 gl_FragColor=texture2D(source,uv);
 vec4 texcolor=texture2D(u_Tex0,v_TexCoord2);
 
 if(texcolor.r>.9){
  gl_FragColor*=texcolor.g>.9?u_Color[0]:u_Color[1];
 }else if(texcolor.g>.9){
  gl_FragColor*=u_Color[2];
 }else if(texcolor.b>.9){
  gl_FragColor*=u_Color[3];
 }
 
 ret=mix(ret,gl_FragColor,gl_FragColor.a);
 ret=mix(m,ret,fade);
 return ret;
}

vec4 background_color=vec4(0.,0.,0.,1.);// : hint_color
vec4 line_color=vec4(0.,1.,1.,1.);//: hint_color
float line_freq=9.56;
float height=.6;
float speed=.8;
vec2 scale=vec2(0.5,4.);

void main(void)
{
 
 float angle=45.;// 255 or 45
 vec2 perspective=rotate(v_TexCoord3,(angle/180.)*3.14);
 
 vec2 uv=perspective*scale;
 float shift=cos(floor(uv.y));
 uv.x+=shift;
 
 float freq=clamp(cos(uv.x*line_freq)*3.,0.,1.)*height;
 float line=1.-clamp(abs(freq-mod(uv.y,1.))*11.,0.,1.);
 
 vec4 FinalResult=mix(background_color,line_color,line*mod(uv.x-u_Time*speed*abs(shift),1.)/*  * mod( TIME + shift, 1.0 ) */);
 
 vec4 txt1=texture2D(u_Tex0,v_TexCoord);
 FinalResult.a=txt1.a;
 
 float _SpriteFade=1.;// ("SpriteFade",Range(0,1))=1.
 float _ShadowLight_Precision_1=14.311;//("_ShadowLight_Precision_1",Range(1,32))=14.311
 float _ShadowLight_Size_1=.05;//("_ShadowLight_Size_1",Range(0,16))=.686
 float _ShadowLight_Intensity_1=.5;//("_ShadowLight_Intensity_1",Range(0,4))=3.664
 float _ShadowLight_PosX_1=0.;//("_ShadowLight_PosX_1",Range(-1,1))=0
 float _ShadowLight_PosY_1=0.;//("_ShadowLight_PosY_1",Range(-1,1))=0
 float _ShadowLight_NoSprite_1=1.;//("_ShadowLight_NoSprite_1",Range(0,1))=1
 vec4 _ShadowLight_Color_1=FinalResult;
 _ShadowLight_Color_1.rgb=line_color.rgb;
 
 vec4 _ShadowLight_1=ShadowLight(u_Tex0,v_TexCoord,_ShadowLight_Precision_1,_ShadowLight_Size_1,_ShadowLight_Color_1,_ShadowLight_Intensity_1,_ShadowLight_PosX_1,_ShadowLight_PosY_1,_ShadowLight_NoSprite_1);
 FinalResult+=_ShadowLight_1;
 FinalResult.a=FinalResult.a*_SpriteFade;
 
 gl_FragColor=FinalResult;
 
}
