uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;
#define pi 3.1415926535897932384626433832795

float shinyPos = 0.0;
float shinySize = -0.1;
float shinySmooth = 1.25;
float shinyIntensity = 0.4;
float shinySpeed = 0.04;
float shinyAngle = 1.25;

float random2d(vec2 coord) {
return fract(sin(dot(coord.xy, vec2(12.9898, 78.233))) * 43758.5453);
}
vec2 rotate(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	mat2 m = mat2(c, -s, s, c);
	return m * v;
}

float atan2(in float y, in float x)
{
    return x == 0.0 ? sign(y)*pi/2.0 : atan(y, x);
}
vec4 ShinyFX(vec4 txt, vec2 uv, float pos, float size, float smooth, float intensity, float speed)
{
return txt;
}
void main()
{
    vec4 texcolorMain = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    if(texcolor.r > 0.9) {
        texcolorMain *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        texcolorMain *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        texcolorMain *= u_Color[3];
    }
	
	vec2 uv = v_TexCoord;
shinyPos = shinyPos + 0.5+sin(u_Time*20.0*shinySpeed)*1.5;
uv = uv - vec2(shinyPos, 1.0);
float a = atan2(uv.x, uv.y) + 2.25, r = 3.1415;
float d = cos(floor(0.5 + a / r) * r - a) * length(uv);
float dist = 1.0 - smoothstep(shinySize, shinySize + shinySmooth, d);
texcolorMain.rgb += dist*shinyIntensity;
	
	gl_FragColor = texcolorMain;
    if(gl_FragColor.a < 0.01) discard;
}