uniform float u_Depth;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

void main()
{
	gl_FragColor = texture2D(u_Tex0, v_TexCoord);

    vec4 effectColor = texture2D(u_Tex1, v_TexCoord3);

	vec4 c = vec4(effectColor.rgb, gl_FragColor.a);

    gl_FragColor.rgb = mix(gl_FragColor.rgb, c.rgb, c.rgb);

	if(gl_FragColor.a < 0.01) discard;
}