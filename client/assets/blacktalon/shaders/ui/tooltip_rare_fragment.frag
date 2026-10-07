uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;
varying vec2 v_Position;

void main()
{
    vec4 textureColor = texture2D(u_Tex0, v_TexCoord);

    // Rare: green glow with flowing light
    vec3 baseColor = vec3(0.6, 0.88, 0.51);

    // Vertical gradient (top to bottom fade)
    float gradientFade = 1.0 - v_TexCoord.y;
    gradientFade = gradientFade * gradientFade;

    // Pulsing glow
    float pulse = 0.8 + 0.2 * sin(u_Time * 1.5);

    // Flowing light wave across horizontally
    float wave = 0.85 + 0.15 * sin(v_TexCoord.x * 6.0 - u_Time * 2.0);

    // Secondary subtle wave for depth
    float wave2 = 0.9 + 0.1 * sin(v_TexCoord.x * 10.0 + u_Time * 1.2);

    vec3 finalRgb = baseColor * pulse * wave * wave2;
    float alpha = gradientFade * 0.35 * textureColor.a;

    gl_FragColor = vec4(finalRgb, alpha) * u_Color;

    if(gl_FragColor.a < 0.01) discard;
}
