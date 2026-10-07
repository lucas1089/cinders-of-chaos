// Name Shadow Shader - Echo/double shadow with oscillating displacement
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

void main()
{
    float time = mod(u_Time, 36000.0);

    // Oscillating shadow displacement
    float shadowSpeed = 2.0;
    float maxDisplace = 0.025;
    vec2 shadowOffset1 = vec2(
        sin(time * shadowSpeed) * maxDisplace,
        cos(time * shadowSpeed * 0.7) * maxDisplace * 0.5
    );
    vec2 shadowOffset2 = vec2(
        sin(time * shadowSpeed * 1.3 + 2.0) * maxDisplace * 0.7,
        cos(time * shadowSpeed * 0.9 + 1.0) * maxDisplace * 0.4
    );

    // Sample main text
    vec4 mainColor = texture2D(u_Tex0, v_TexCoord);

    // Sample shadow echoes at offset positions (clamped to valid UV range)
    vec4 shadow1 = texture2D(u_Tex0, clamp(v_TexCoord - shadowOffset1, vec2(0.0), vec2(1.0)));
    vec4 shadow2 = texture2D(u_Tex0, clamp(v_TexCoord - shadowOffset2, vec2(0.0), vec2(1.0)));

    // Shadow colors - dark purple and dark blue
    vec3 shadow1Color = vec3(0.3, 0.1, 0.5);
    vec3 shadow2Color = vec3(0.1, 0.15, 0.4);

    // Main text color - silver/white with subtle animation
    float shimmer = sin(v_TexCoord.x * 10.0 + time * 3.0) * 0.1 + 0.9;
    vec3 mainTextColor = vec3(0.9, 0.88, 0.95) * shimmer;

    // Compose layers: shadows behind, main text on top
    vec3 finalColor = vec3(0.0);
    float finalAlpha = 0.0;

    // Layer shadow 2 (furthest back, most transparent)
    if (shadow2.a > 0.01) {
        float s2Alpha = shadow2.a * 0.3;
        float luminance2 = dot(shadow2.rgb, vec3(0.299, 0.587, 0.114));
        finalColor = shadow2Color * (luminance2 * 0.5 + 0.5);
        finalAlpha = s2Alpha;
    }

    // Layer shadow 1 (middle layer)
    if (shadow1.a > 0.01) {
        float s1Alpha = shadow1.a * 0.5;
        float luminance1 = dot(shadow1.rgb, vec3(0.299, 0.587, 0.114));
        vec3 s1Color = shadow1Color * (luminance1 * 0.5 + 0.5);
        finalColor = mix(finalColor, s1Color, s1Alpha);
        finalAlpha = max(finalAlpha, s1Alpha);
    }

    // Layer main text (front)
    if (mainColor.a > 0.01) {
        float luminance = dot(mainColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 mColor = mainTextColor * (luminance * 0.4 + 0.6);
        finalColor = mix(finalColor, mColor, mainColor.a);
        finalAlpha = max(finalAlpha, mainColor.a);
    }

    if (finalAlpha < 0.01) {
        discard;
    }

    gl_FragColor = vec4(finalColor, finalAlpha);
}
