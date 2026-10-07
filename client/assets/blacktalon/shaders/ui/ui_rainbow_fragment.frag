uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;
uniform vec4 u_Color;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;
varying vec2 v_Position;

void main()
{
    // Get the texture color
    vec4 textureColor = texture2D(u_Tex0, v_TexCoord);
    
    // Create rainbow effect based on position and time
    float rainbowOffset = (v_Position.x + v_Position.y + u_Time * 0.5) * 0.5;
    vec3 rainbow = vec3(
        0.5 + 0.5 * sin(rainbowOffset),
        0.5 + 0.5 * sin(rainbowOffset + 2.0),
        0.5 + 0.5 * sin(rainbowOffset + 4.0)
    );
    
    // Apply rainbow only to opaque parts of the texture
    vec4 finalColor = vec4(textureColor.rgb * rainbow, textureColor.a);
    
    // Apply UI element's color
    gl_FragColor = finalColor * u_Color;
} 