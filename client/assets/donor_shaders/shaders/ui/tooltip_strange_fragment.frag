uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;
varying vec2 v_Position;

void main()
{
    vec4 textureColor = texture2D(u_Tex0, v_TexCoord);

    // Strange: subtle gray-green shimmer
    vec3 baseColor = vec3(0.77, 0.81, 0.74);

    // Gentle vertical gradient (top to bottom fade)
    float gradientFade = 1.0 - v_TexCoord.y;
    gradientFade = gradientFade * gradientFade; // quadratic falloff

    // Subtle pulse
    float pulse = 0.85 + 0.15 * sin(u_Time * 1.2);

    // Soft horizontal shimmer wave
    float shimmer = 0.9 + 0.1 * sin(v_TexCoord.x * 8.0 + u_Time * 1.5);

    vec3 finalRgb = baseColor * pulse * shimmer;
    float alpha = gradientFade * 0.25 * textureColor.a;

    gl_FragColor = vec4(finalRgb, alpha) * u_Color;

    if(gl_FragColor.a < 0.01) discard;
}
