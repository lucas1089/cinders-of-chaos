uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;
#define pi 3.1415926535897932384626433832795

float random2d(vec2 coord) {
return fract(sin(dot(coord.xy, vec2(12.9898, 78.233))) * 43758.5453);
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
	coord += translate;
	
	colorRing.r += abs(0.1 + length(coord) - 0.25 * abs(sin(u_Time * 1.6 / 2.0)));
	colorRing.g += abs(0.1 + length(coord) - 0.25 * abs(sin(u_Time * 1.6 / 2.0)));
	colorRing.b += abs(0.1 + length(coord) - 0.25 * abs(sin(u_Time * 1.6 / 2.0)));
	vec3 color = vec3(0.1 / colorRing);
	vec4 overlaper = mix( texcolorMain, vec4(color,0.08), texcolorMain.a );
	gl_FragColor = overlaper * overlaper.a + texcolorMain * (1.0 - overlaper.a);
    if(gl_FragColor.a < 0.01) discard;
}