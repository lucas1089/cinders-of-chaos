uniform float u_Time;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;

vec4 EmbossFull(sampler2D txt,vec2 uv,float angle,float dist,float intensity,float g,float o,vec4 color)
{
 angle=angle*3.1415926;
 intensity=intensity*.25;
 #define rot(n)(n*mat2(cos(angle),-sin(angle),sin(angle),cos(angle)))
 float m1=0.;float m2=0.;float m3=0.;
 float m4=0.;float m5=1.;float m6=0.;
 float m7=0.;float m8=0.;float m9=-1.;
 float Offset=.5;
 float Scale=1.;
 vec4 r=vec4(0,0,0,0);
 dist=dist*.005;
 vec4 rgb=texture2D(txt,uv);
 r+=texture2D(txt,uv+rot(vec2(-dist,-dist)))*m1*intensity;
 r+=texture2D(txt,uv+rot(vec2(0,-dist)))*m2*intensity;
 r+=texture2D(txt,uv+rot(vec2(dist,-dist)))*m3*intensity;
 r+=texture2D(txt,uv+rot(vec2(-dist,0)))*m4*intensity;
 r+=texture2D(txt,uv+rot(vec2(0,0)))*m5*intensity;
 r+=texture2D(txt,uv+rot(vec2(dist,0)))*m6*intensity;
 r+=texture2D(txt,uv+rot(vec2(-dist,dist)))*m7*intensity;
 r+=texture2D(txt,uv+rot(vec2(0,dist)))*m8*intensity;
 r+=texture2D(txt,uv+rot(vec2(dist,dist)))*m9*intensity;
 // r=mix(r,dot(r.rgb,3.0),g);
 // r=mix(r+.5,rgb+r,o);
 r=clamp(r,0.,1.);// OPTIONAL
 r=r*6.;
 r.a=rgb.a;
 return r*color;
}

vec4 EmbossOutline(sampler2D txt,vec2 uv,float angle,float dist,float intensity,float g,float o,vec4 color)
{
 angle=angle*3.1415926;
 intensity=intensity*.25;
 #define rot(n)(n*mat2(cos(angle),-sin(angle),sin(angle),cos(angle)))
 float m1=0.;float m2=0.;float m3=0.;
 float m4=0.;float m5=1.;float m6=0.;
 float m7=0.;float m8=0.;float m9=-1.;
 float Offset=.5;
 float Scale=1.;
 vec4 r=color;
 dist=dist*.005;
 vec4 rgb=texture2D(txt,uv);
 r+=texture2D(txt,uv+rot(vec2(-dist,-dist)))*m1*intensity;
 r+=texture2D(txt,uv+rot(vec2(0,-dist)))*m2*intensity;
 r+=texture2D(txt,uv+rot(vec2(dist,-dist)))*m3*intensity;
 r+=texture2D(txt,uv+rot(vec2(-dist,0)))*m4*intensity;
 r+=texture2D(txt,uv+rot(vec2(0,0)))*m5*intensity;
 r+=texture2D(txt,uv+rot(vec2(dist,0)))*m6*intensity;
 r+=texture2D(txt,uv+rot(vec2(-dist,dist)))*m7*intensity;
 r+=texture2D(txt,uv+rot(vec2(0,dist)))*m8*intensity;
 r+=texture2D(txt,uv+rot(vec2(dist,dist)))*m9*intensity;
 // r=mix(r,dot(r.rgb,3.0),g);
 // r=mix(r+.5,rgb+r,o);
 r=clamp(r,0.,1.);// OPTIONAL
 r=r*6.;
 r.a=rgb.a;
 return r;
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

void main(void)
{
 
 gl_FragColor=texture2D(u_Tex0,v_TexCoord);
 vec4 texcolor=texture2D(u_Tex0,v_TexCoord2);
 vec4 effectColor=texture2D(u_Tex1,v_TexCoord3);
 
 float _EmbossFull_Angle_1=u_Time;// ("_EmbossFull_Angle_1",Range(-1,1))=0
 float _EmbossFull_Distance_1=.3;// ("_EmbossFull_Distance_1",Range(0,16))=.3
 float _EmbossFull_Intensity_1=3.;// ("_EmbossFull_Intensity_1",Range(-2,2))=1
 float _EmbossFull_grayfade_1=2.;// ("_EmbossFull_grayfade_1",Range(-2,2))=1
 float _EmbossFull_original_1=1.;// ("_EmbossFull_original_1",Range(-2,2))=1
 float _SpriteFade=1.;// ("SpriteFade",Range(0,1))=1.
 vec4 _color=vec4(1.0, 0.0, 0.0, 1.0);
 
 vec4 _EmbossFull_1=EmbossFull(u_Tex0,v_TexCoord,_EmbossFull_Angle_1,_EmbossFull_Distance_1,_EmbossFull_Intensity_1,_EmbossFull_grayfade_1,_EmbossFull_original_1,_color);
 vec4 FinalResult=_EmbossFull_1;
 FinalResult.a=FinalResult.a*_SpriteFade;
 
 float _ShadowLight_Precision_1=14.311;//("_ShadowLight_Precision_1",Range(1,32))=14.311
 float _ShadowLight_Size_1=.05;//("_ShadowLight_Size_1",Range(0,16))=.686
 vec4 _ShadowLight_Color_1=EmbossOutline(u_Tex0,v_TexCoord,_EmbossFull_Angle_1,_EmbossFull_Distance_1,_EmbossFull_Intensity_1,_EmbossFull_grayfade_1,_EmbossFull_original_1,_color);
 float _ShadowLight_Intensity_1=0.5;//("_ShadowLight_Intensity_1",Range(0,4))=3.664
 float _ShadowLight_PosX_1=0.;//("_ShadowLight_PosX_1",Range(-1,1))=0
 float _ShadowLight_PosY_1=0.;//("_ShadowLight_PosY_1",Range(-1,1))=0
 float _ShadowLight_NoSprite_1=1.;//("_ShadowLight_NoSprite_1",Range(0,1))=1
 
 vec4 _ShadowLight_1=ShadowLight(u_Tex0,v_TexCoord,_ShadowLight_Precision_1,_ShadowLight_Size_1,_ShadowLight_Color_1,_ShadowLight_Intensity_1,_ShadowLight_PosX_1,_ShadowLight_PosY_1,_ShadowLight_NoSprite_1);
 FinalResult+=_ShadowLight_1;
 FinalResult.a=FinalResult.a*_SpriteFade;
 
 gl_FragColor=FinalResult;
 
}
