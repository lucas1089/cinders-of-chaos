uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

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
   vec2 coord = v_TexCoord.xy * 12.5;
   coord -= u_Time + vec2(sin(coord.y),cos(coord.x));
	
	float rand01 = fract(random2d(floor(coord)) + u_Time / 60.0);
	float rand02 = fract(random2d(floor(coord)) + u_Time / 40.0);
	
	rand01 *= 0.4 - length(fract(coord));
	vec3 color = vec3(rand01 *4.0,rand02 * rand01 * 4.0,0.0);
	
	vec4 overlaper = mix( texcolorMain, vec4(color,0.18), texcolorMain.a );
	gl_FragColor = overlaper * overlaper.a + texcolorMain * (1.0 - overlaper.a);
    if(gl_FragColor.a < 0.01) discard;
}