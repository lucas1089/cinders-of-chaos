uniform float u_Time;
uniform vec2 u_Resolution;

void main()
{
    vec2 uv = gl_FragCoord.xy / u_Resolution;

    // Bright band travelling along the line (vertical shimmer)
    float shine = sin(uv.y * 8.0 - u_Time * 4.0) * 0.5 + 0.5;

    vec3 gold = vec3(1.0, 0.85, 0.35);
    vec3 darkGold = vec3(0.45, 0.32, 0.08);
    vec3 color = mix(darkGold, gold, shine);

    gl_FragColor = vec4(color, 1.0);
}
