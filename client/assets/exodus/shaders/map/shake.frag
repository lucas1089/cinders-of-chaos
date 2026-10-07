uniform float u_Time;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;

const float PI=3.1415926535897932;

vec3 RotateAroundAxis(vec3 center,vec3 original,vec3 u,float angle)
{
 original-=center;
 float C=cos(angle);
 float S=sin(angle);
 float t=1.-C;
 float m00=t*u.x*u.x+C;
 float m01=t*u.x*u.y-S*u.z;
 float m02=t*u.x*u.z+S*u.y;
 float m10=t*u.x*u.y+S*u.z;
 float m11=t*u.y*u.y+C;
 float m12=t*u.y*u.z-S*u.x;
 float m20=t*u.x*u.z-S*u.y;
 float m21=t*u.y*u.z+S*u.x;
 float m22=t*u.z*u.z+C;
 mat3 finalMatrix=mat3(m00,m01,m02,m10,m11,m12,m20,m21,m22);
 return vec3(finalMatrix*original)+center;
}

void main(void)
{
 
 vec2 _SineRotatePivot=vec2(.5,.5);//("Sine Rotate: Pivot", Vector) = (0.5,0.5,0,0)
 float _SineRotateFrequency=20.;// ("Sine Rotate: Frequency", Float) = 1
 float _SineRotateFade=0.1;// ("Sine Rotate: Fade", Range( 0 , 1)) = 1
 float _SineRotateAngle=15.;// ("Sine Rotate: Angle", Float) = 15
 
 gl_FragColor=texture2D(u_Tex0,v_TexCoord);
 
 float staticSwitch1_g31=u_Time;
 
 vec2 texCoord35=v_TexCoord.xy*vec2(1,1)+vec2(0,0);
 vec3 rotatedValue36_g22=RotateAroundAxis(vec3(_SineRotatePivot,0.),vec3(texCoord35,0.),vec3(0,0,1),(sin((staticSwitch1_g31*_SineRotateFrequency))*((_SineRotateAngle/360.)*PI)*_SineRotateFade));
 
 vec4 c=(texture2D(u_Tex0,(rotatedValue36_g22).xy));
 c.rgb*=c.a;
 
 gl_FragColor=c;
 
}