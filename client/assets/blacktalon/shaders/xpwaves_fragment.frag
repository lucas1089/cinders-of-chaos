uniform float u_Time;
uniform vec2 u_Resolution;

void main()
{
    vec2 uv = gl_FragCoord.xy / u_Resolution;

    // Slow, smooth looping motion
    float slowTime = u_Time * 0.2;
    float waveX = sin(uv.y * 5.0 + slowTime) * 0.1;
    float waveY = cos(uv.x * 5.0 + slowTime) * 0.1;

    // Combine the waves into continuous diagonal lines
    float lines = sin((uv.x + waveX + waveY) * 200.0) * 0.5 + 0.5;

    // Red / dark red
    vec3 red = vec3(1.0, 0.0, 0.0);
    vec3 darkRed = vec3(0.5, 0.0, 0.0);
    vec3 color = mix(darkRed, red, lines);

    // Fully opaque (unlike redwaves which forces alpha 0.5)
    gl_FragColor = vec4(color, 1.0);
}
