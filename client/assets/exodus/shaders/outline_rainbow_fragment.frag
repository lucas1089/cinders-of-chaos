uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform float u_Time;

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

    vec2 texel = vec2(1.0/512.0, 1.0/512.0);

    float leftPixel = texture2D(u_Tex0, v_TexCoord + vec2(-texel.x, 0.0)).a;
    float upPixel = texture2D(u_Tex0, v_TexCoord + vec2(0.0, texel.y)).a;
    float rightPixel = texture2D(u_Tex0, v_TexCoord + vec2(texel.x, 0.0)).a;
    float bottomPixel = texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texel.y)).a;

    float outline = (1. - leftPixel * upPixel * rightPixel * bottomPixel) * gl_FragColor.a;
    
    vec4 col;
	col.r = sin(.6 * (v_TexCoord.y * 150.0) + mod(u_Time, 3600.0) * 10. + 0.) * 0.5 + 0.5;
	col.g = sin(.6 * (v_TexCoord.y * 150.0) + mod(u_Time, 3600.0) * 10. + 2.) * 0.5 + 0.5;
	col.b = sin(.6 * (v_TexCoord.y * 150.0)  + mod(u_Time, 3600.0) * 10. + 4.) * 0.5 + 0.5;
    col.a = 1.0;

    gl_FragColor = mix(gl_FragColor, col, outline);

    if(gl_FragColor.a < 0.01) discard;
}
