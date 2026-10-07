uniform float u_Depth;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;
uniform float u_Time;

float random(in float a, in float b) { return fract((cos(dot(vec2(a,b) ,vec2(12.9898,78.233))) * 43758.5453)); }

void main()
{
	gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    if(texcolor.r > 0.9) {
        gl_FragColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        gl_FragColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        gl_FragColor *= u_Color[3];
    }
	
	vec2 pos = v_TexCoord;
	
    vec3 col;

    col.r = texture2D(u_Tex0, vec2(pos.x + 0.015 * sin(0.02 * mod(u_Time, 3600.0)), pos.y)).x;
    col.g = texture2D(u_Tex0, vec2(pos.x , pos.y)).y;
    col.b = texture2D(u_Tex0, vec2(pos.x - 0.015 * sin(0.02 * mod(u_Time, 3600.0)), pos.y)).z;	
	
	float c = 1.;
	
	c += 6. * sin(mod(u_Time, 3600.0) * 4. + pos.y * 1000.);
	c += 3. * sin(mod(u_Time, 3600.0) * 1. + pos.y * 800.);
	c += 20. * sin(mod(u_Time, 3600.0) * 10. + pos.y * 9000.);
	
	c += 1. * cos(mod(u_Time, 3600.0) * 1. + pos.x * 1.);
	
	pos += u_Time;
	
	float r = random(pos.x, 	pos.y);
	float g = random(pos.x * 9., 	pos.y * 9.);
	float b = random(pos.x * 3., 	pos.y * 3.);
	
	gl_FragColor *= vec4(col.x * r*c * .35, col.y * b * c * .35, col.z * g * c * .35, 1);
	if(gl_FragColor.a < 0.01) discard;
}