// Name Gradient Blue Shader - Animated white-blue sweep for text rendering
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const float PI = 3.14159265359;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only process visible text pixels
    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // White and Blue color endpoints
    vec3 white = vec3(1.0, 1.0, 1.0);
    vec3 blue = vec3(0.0, 0.25, 1.0); // #0040FF

    // Scrolling sweep: moves left to right over ~2 seconds
    float timeOffset = fract(time * 0.5); // 0.5 = 1/2s cycle period -> 2 second full cycle

    // Combine horizontal position with time for sweep
    float phase = fract(v_TexCoord.x + timeOffset);

    // Smooth wave using sine (0.0 to 1.0 range)
    float t = (sin(phase * 2.0 * PI) + 1.0) / 2.0;

    // Interpolate between blue and white
    vec3 gradientColor = mix(blue, white, t);

    // Apply to text preserving luminance (dark outline stays dark)
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = gradientColor * (luminance * 0.3 + 0.7);

    gl_FragColor = vec4(finalColor, texColor.a);
}
