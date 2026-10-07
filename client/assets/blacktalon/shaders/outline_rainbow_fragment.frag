uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_Position;
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec2 u_Resolution;
uniform float u_spriteSize;

float line_thickness = 2.0;

void main()
{
	vec2 size = line_thickness*vec2(1.0/512.0, 1.0/512.0);
	
	float outline = texture2D(u_Tex0, v_TexCoord + vec2(-size.x, 0)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(0, size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, 0)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(0, -size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(-size.x, size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(-size.x, -size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, -size.y)).a;
	outline = min(outline, 1.0);

	vec4 outline_colour;
	outline_colour.r = sin(.6 * (v_TexCoord.y * 150.0) + mod(u_Time, 3600.0) * 10. + 0.) * 0.5 + 0.5;
	outline_colour.g = sin(.6 * (v_TexCoord.y * 150.0) + mod(u_Time, 3600.0) * 10. + 2.) * 0.5 + 0.5;
	outline_colour.b = sin(.6 * (v_TexCoord.y * 150.0)  + mod(u_Time, 3600.0) * 10. + 4.) * 0.5 + 0.5;
    outline_colour.a = 1.0;

	gl_FragColor = texture2D(u_Tex0, v_TexCoord);
	gl_FragColor = mix(gl_FragColor, outline_colour, outline - gl_FragColor.a);

    if(gl_FragColor.a < 0.01) discard;
}