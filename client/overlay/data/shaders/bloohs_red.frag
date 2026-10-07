uniform float u_Time;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;

vec4 ColorTurnMetal(vec2 uv,sampler2D txt,float speed,vec4 color)
{
 vec4 txt1=texture2D(txt,uv);
 vec2 tuv=uv;
 uv*=2.5;
 float time=(u_Time/4.)*speed;
 float a=time*50.;
 float n=sin(a+2.*uv.x)+sin(a-2.*uv.x)+sin(a+2.*uv.y)+sin(a+5.*uv.y);
 n+=texture2D(txt,tuv).r*.21+texture2D(txt,tuv).g*.4+texture2D(txt,tuv).b*.2;
 n=mod(n,1.);
 float tx=n*6.;
 float r=clamp(tx-2.,0.,1.)+clamp(2.-tx,0.,1.);
 vec4 sortie=vec4(1.,1.,1.,r);
 sortie.rgb=vec3(0).rgb+(1.-sortie.a);
 sortie.rgb=.05+sortie.rgb*.5+dot(sortie.rgb,vec3(.2126,.2152,.1722))*.5;
 sortie.a=txt1.a;
 return sortie*color;
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
 float time=(sin(u_Time));
 
 // vec2 center=(gl_FragCoord.xy/u_Resolution.xy);
 // vec2 translate=vec2(-.5);
 // center+=translate;
 
 float _TurnMetal_Speed_1=.05;// ("_TurnMetal_Speed_1",Range(-8,8))=1
 float _SpriteFade=1.;// ("SpriteFade",Range(0,1))=1.
 
 vec4 _color=vec4(0.8706, 0.2157, 0.051, 1.0);
 
 vec4 _TurnMetal_1=ColorTurnMetal(v_TexCoord,u_Tex0,_TurnMetal_Speed_1,_color);
 vec4 FinalResult=_TurnMetal_1;
 FinalResult.a=FinalResult.a*_SpriteFade;
 
 float _ShadowLight_Precision_1=14.311;//("_ShadowLight_Precision_1",Range(1,32))=14.311
 float _ShadowLight_Size_1=.05;//("_ShadowLight_Size_1",Range(0,16))=.686
 float _ShadowLight_Intensity_1=.5;//("_ShadowLight_Intensity_1",Range(0,4))=3.664
 float _ShadowLight_PosX_1=0.;//("_ShadowLight_PosX_1",Range(-1,1))=0
 float _ShadowLight_PosY_1=0.;//("_ShadowLight_PosY_1",Range(-1,1))=0
 float _ShadowLight_NoSprite_1=1.;//("_ShadowLight_NoSprite_1",Range(0,1))=1
 vec4 _ShadowLight_Color_1=FinalResult;
 _ShadowLight_Color_1.rgb=_color.rgb;
 
 vec4 _ShadowLight_1=ShadowLight(u_Tex0,v_TexCoord,_ShadowLight_Precision_1,_ShadowLight_Size_1,_ShadowLight_Color_1,_ShadowLight_Intensity_1,_ShadowLight_PosX_1,_ShadowLight_PosY_1,_ShadowLight_NoSprite_1);
 FinalResult+=_ShadowLight_1;
 FinalResult.a=FinalResult.a*_SpriteFade;
 
 gl_FragColor=FinalResult;
 
}
