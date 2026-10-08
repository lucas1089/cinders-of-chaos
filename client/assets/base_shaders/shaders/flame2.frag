uniform float u_Time;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform vec2 u_Offset;
uniform vec2 u_Center;

// We are generating our own noise here. You could experiment with the
// built in SimplexNoise or your own noise texture for other effects.

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

// uniform sampler2D noise_tex:hint_white;
vec4 root_color=vec4(1.,.75,.3,1.) *0.8;// :hint_color=vec4(1.,.75,.3,1.);
vec4 tip_color=vec4(1.,.03,.001,1.) *0.15;// :hint_color=vec4(1.,.03,.001,1.);
float fire_alpha=.5;//:hint_range(0.,1.)=1.;
vec2 fire_speed=vec2(0.,1.);
float fire_aperture=.1;// :hint_range(0.,3.)=.22;

void main(void)
{
 
 gl_FragColor=texture2D(u_Tex0,v_TexCoord);
 vec4 texcolor=texture2D(u_Tex0,v_TexCoord2);
 
 if(texcolor.r>.9){
  gl_FragColor*=texcolor.g>.9?u_Color[0]:u_Color[1];
 }else if(texcolor.g>.9){
  gl_FragColor*=u_Color[2];
 }else if(texcolor.b>.9){
  gl_FragColor*=u_Color[3];
 }
 
 float time=(sin(u_Time));
 
 float angle=315.;// degrees
 vec2 perspective=rotate(v_TexCoord3,(angle/180.)*3.14);
 
 vec2 shifted_uv=perspective+u_Time*fire_speed;
 float fire_noise=texture2D(u_Tex1,shifted_uv).r;
 float noise=perspective.y*(((perspective.y+fire_aperture)*fire_noise-fire_aperture)*75.);
 vec4 fire_color=mix(tip_color,root_color,noise*.05);
 
 float ALPHA=clamp(noise,0.,1.)*fire_alpha;
 vec3 ALBEDO=fire_color.rgb;
 
 vec4 fire;
 fire.rgb=ALBEDO;
 

 // BORDA
 float _ShadowLight_Precision_1=14.311;//("_ShadowLight_Precision_1",Range(1,32))=14.311
 float _ShadowLight_Size_1=.1;//("_ShadowLight_Size_1",Range(0,16))=.686
 float _ShadowLight_Intensity_1=.6;//("_ShadowLight_Intensity_1",Range(0,4))=3.664
 float _ShadowLight_PosX_1=0.;//("_ShadowLight_PosX_1",Range(-1,1))=0
 float _ShadowLight_PosY_1=0.;//("_ShadowLight_PosY_1",Range(-1,1))=0
 float _ShadowLight_NoSprite_1=1.;//("_ShadowLight_NoSprite_1",Range(0,1))=1
 vec4 _ShadowLight_Color_1=fire;
 _ShadowLight_Color_1.rgb=root_color.rgb;
 vec4 _ShadowLight_1=ShadowLight(u_Tex0,v_TexCoord,_ShadowLight_Precision_1,_ShadowLight_Size_1,_ShadowLight_Color_1,_ShadowLight_Intensity_1,_ShadowLight_PosX_1,_ShadowLight_PosY_1,_ShadowLight_NoSprite_1);
 fire+=_ShadowLight_1;
 fire.a=fire.a*1.;
 
 gl_FragColor=fire;
 
}
