uniform float u_Time;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;

vec4 ColorFilters(vec4 rgba,vec4 red,vec4 green,vec4 blue,float fade)
{
 vec3 c_r=vec3(red.r,red.g,red.b);
 vec3 c_g=vec3(green.r,green.g,green.b);
 vec3 c_b=vec3(blue.r,blue.g,blue.b);
 vec4 r=vec4(dot(rgba.rgb,c_r)+red.a,dot(rgba.rgb,c_g)+green.a,dot(rgba.rgb,c_b)+blue.a,rgba.a);
 return mix(rgba,(r),fade);
 
}

void main(void)
{
 
 gl_FragColor=texture2D(u_Tex0,v_TexCoord);
 
 float time=abs(sin(u_Time));
 
 float _ColorFilters_Fade_1=1.;// ("_ColorFilters_Fade_1", Range(0, 1)) = 1
 float _SpriteFade=1.;// ("SpriteFade", Range(0, 1)) = 1.0
 
 vec4 _MainTex_1=texture2D(u_Tex0,v_TexCoord);

 vec4 _ColorFilters_1=ColorFilters(_MainTex_1,vec4(2,-2,-2,-2),vec4(1.95,.04,-1.6,.1),vec4(2,-2,-2,-2),_ColorFilters_Fade_1);
 vec4 FinalResult=_ColorFilters_1;
 // FinalResult.rgb*=i.color.rgb;
 FinalResult.a=FinalResult.a*_SpriteFade;
 
 gl_FragColor=FinalResult;
 
}
