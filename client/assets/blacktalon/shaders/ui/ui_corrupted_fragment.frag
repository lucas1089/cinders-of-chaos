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

    // Create pulsing corruption effect with multiple frequencies
    float pulse1 = 0.6 + 0.4 * sin(u_Time * 3.0);
    float pulse2 = 0.7 + 0.3 * sin(u_Time * 1.5 + 1.57);
    float pulseIntensity = (pulse1 + pulse2) * 0.5;

    // Dark magenta/purple corruption color (#8f0362)
    vec3 corruptColor = vec3(0.56, 0.02, 0.38) * pulseIntensity;

    // Apply corruption color to the texture
    vec4 finalColor = vec4(textureColor.rgb * corruptColor * 1.8, textureColor.a);

    // Apply UI element's color
    gl_FragColor = finalColor * u_Color;
}
