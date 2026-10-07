uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_Position;
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec2 u_Resolution;
uniform float u_spriteSize;

float line_thickness = 3.0;

void main()
{
	vec2 size = line_thickness * vec2(1.0 / 512.0, 1.0 / 512.0);

	// Sample neighbors for outline detection
	float outline = texture2D(u_Tex0, v_TexCoord + vec2(-size.x, 0)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(0, size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, 0)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(0, -size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(-size.x, size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(-size.x, -size.y)).a;
	outline += texture2D(u_Tex0, v_TexCoord + vec2(size.x, -size.y)).a;
	outline = min(outline, 1.0);

	// Static gold outline (no pulsing / blinking)
	vec3 brightGold = vec3(1.0, 0.84, 0.3);
	vec3 warmAmber = vec3(0.85, 0.55, 0.1);
	vec3 goldColor = mix(warmAmber, brightGold, 0.7);

	vec4 outline_colour;
	outline_colour.rgb = goldColor;
	outline_colour.a = 0.85;

	gl_FragColor = texture2D(u_Tex0, v_TexCoord);
	gl_FragColor = mix(gl_FragColor, outline_colour, outline - gl_FragColor.a);

	if (gl_FragColor.a < 0.01) discard;
}
