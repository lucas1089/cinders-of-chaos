uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;
varying vec2 v_Position;

void main()
{
    vec4 textureColor = texture2D(u_Tex0, v_TexCoord);

    // Epic: red/crimson with fiery pulse
    vec3 baseColor = vec3(0.89, 0.13, 0.13);
    vec3 accentColor = vec3(1.0, 0.3, 0.1);

    // Vertical gradient (top to bottom fade)
    float gradientFade = 1.0 - v_TexCoord.y;
    gradientFade = gradientFade * gradientFade;

    // Pulsing intensity
    float pulse = 0.75 + 0.25 * sin(u_Time * 2.0);

    // Fiery flowing wave
    float wave = sin(v_TexCoord.x * 8.0 - u_Time * 2.5) * 0.5 + 0.5;
    float wave2 = sin(v_TexCoord.x * 12.0 + u_Time * 1.8) * 0.5 + 0.5;

    // Mix base and accent based on wave
    vec3 finalRgb = mix(baseColor, accentColor, wave * 0.3 + wave2 * 0.15) * pulse;

    // Brighter at the very top
    float topGlow = max(0.0, 1.0 - v_TexCoord.y * 3.0);
    finalRgb += accentColor * topGlow * 0.2;

    float alpha = gradientFade * 0.4 * textureColor.a;

    gl_FragColor = vec4(finalRgb, alpha) * u_Color;

    if(gl_FragColor.a < 0.01) discard;
}
