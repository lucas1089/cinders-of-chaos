uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;
#define pi 3.1415926535897932384626433832795
void main()
{
    vec4 mainColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    if(texcolor.r > 0.9) {
        mainColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        mainColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        mainColor *= u_Color[3];
    }	
   vec2 coord = vec2(gl_FragCoord.xy/ u_Resolution);
	vec3 color = vec3(0.0);
	
	float angle = atan(-coord.y + 0.25, coord.x - 0.9) * 0.1;
	float len = length(coord - vec2(0.9,1.25));
	
	color.r += sin(len * 100.0 + angle * 100.0 + u_Time*2.5);
	color.g += cos(len * 700.0 + angle * 100.0 + u_Time*2.5);
	color.b += sin(len * 125.0 + angle * 125.0 + 3.0);
	vec4 overlaper = mix( mainColor, vec4(color,0.17), mainColor.a );
	gl_FragColor = overlaper * overlaper.a + mainColor * (1.0 - overlaper.a);
    if(gl_FragColor.a < 0.01) discard;
}