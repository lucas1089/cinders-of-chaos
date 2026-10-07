uniform float u_Time;
uniform vec4 u_Color;

varying vec2 v_TexCoord;
varying vec2 v_Position;

void main()
{
    float x = v_TexCoord.x;

    // Base colors: dark blue (left) to light blue (right)
    vec3 darkBlue = vec3(0.08, 0.18, 0.45);
    vec3 lightBlue = vec3(0.25, 0.65, 0.95);
    vec3 baseColor = mix(darkBlue, lightBlue, x);

    // Animated wave: bright streak that moves left to right
    float wave = sin((x * 6.0) - (u_Time * 2.5)) * 0.5 + 0.5;
    wave = pow(wave, 3.0); // sharpen the wave peaks

    // Secondary slower wave for depth
    float wave2 = sin((x * 3.0) + (u_Time * 1.2)) * 0.5 + 0.5;
    wave2 = pow(wave2, 2.0);

    // Combine: base gradient + animated highlights
    vec3 highlight = vec3(0.4, 0.75, 1.0);
    vec3 finalColor = baseColor + highlight * wave * 0.25 + highlight * wave2 * 0.1;

    // Subtle vertical gradient for depth (brighter center)
    float y = v_TexCoord.y;
    float vGrad = 1.0 - abs(y - 0.5) * 0.6;
    finalColor *= vGrad;

    gl_FragColor = vec4(finalColor, 1.0) * u_Color;
}
