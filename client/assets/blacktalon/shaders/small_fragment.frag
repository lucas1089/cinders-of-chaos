uniform float u_Depth;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;
uniform float u_Time;

void main()
{
    // Sample the texture at the current texture coordinate
    gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    
    // Apply color matrix transforms for color regions (if needed)
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    if(texcolor.r > 0.9) {
        gl_FragColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        gl_FragColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        gl_FragColor *= u_Color[3];
    }
    
    // Discard fully transparent pixels
    if(gl_FragColor.a < 0.01) discard;
} 