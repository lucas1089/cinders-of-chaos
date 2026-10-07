uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

float _PlasmaFX_Fade_1 = 0.5;
float _PlasmaFX_Speed_1 = 0.4;


float RBFXmod(float x,float modu)
{
return x - floor(x * (1.0 / modu)) * modu;
}

vec3 RBFXrainbow(float t)
{
t= RBFXmod(t,1.0);
float tx = t * 8.0;
float r = clamp(tx - 4.0, 0.0, 1.0) + clamp(2.0 - tx, 0.0, 1.0);
float g = tx < 2.0 ? clamp(tx, 0.0, 1.0) : clamp(4.0 - tx, 0.0, 1.0);
float b = tx < 4.0 ? clamp(tx - 2.0, 0.0, 1.0) : clamp(6.0 - tx, 0.0, 1.0);
return vec3(r, g, b);
}

vec4 Plasma(vec4 txt, vec2 uv, float _Fade, float speed)
{
float _TimeX= u_Time * speed;
float a = 1.1 + _TimeX * 2.25;
float b = 0.5 + _TimeX * 1.77;
float c = 8.4 + _TimeX * 1.58;
float d = 610.0 + _TimeX * 2.03;
float x1 = 2.0 * uv.x;
float n = sin(a + x1) + sin(b - x1) + sin(c + 2.0 * uv.y) + sin(d + 5.0 * uv.y);
n = RBFXmod(((5.0 + n) / 5.0), 1.0);
vec4 nx=txt;
n += nx.r * 0.2 + nx.g * 0.4 + nx.b * 0.2;
vec4 ret=vec4(RBFXrainbow(n),txt.a);
return mix(txt,ret,_Fade);
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
   vec2 coord = (gl_FragCoord.xy / u_Resolution.xy);
	vec3 colorRing = vec3(0.0);
	vec2 translate = vec2(-0.5);
	
vec4 _MainTex_1 = texture2D(u_Tex0,v_TexCoord);
vec4 _PlasmaFX_1 = Plasma(_MainTex_1,v_TexCoord,_PlasmaFX_Fade_1,_PlasmaFX_Speed_1);
gl_FragColor = _PlasmaFX_1;
gl_FragColor.rgb *= _MainTex_1.rgb;
gl_FragColor.a = gl_FragColor.a * _MainTex_1.a;

	vec3 color = vec3(0.1 / colorRing);
	vec4 overlaper = mix( texcolorMain, vec4(color,0.08), texcolorMain.a );
}