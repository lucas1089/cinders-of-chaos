varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_var0; // saturation: 0.0 = grayscale, 1.0 = full color
uniform vec2 u_Resolution;

void main()
{
    // Gaussian blur (5x5 kernel)
    vec2 pixelSize = 1.0 / u_Resolution;
    float radius = 3.0;
    float sigma = 3.0;

    vec4 color = vec4(0.0);
    float weightSum = 0.0;

    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            float distSq = float(x * x + y * y);
            float weight = exp(-distSq / (2.0 * sigma * sigma));
            vec2 offset = vec2(float(x), float(y)) * pixelSize * radius;
            color += texture2D(u_Tex0, v_TexCoord + offset) * weight;
            weightSum += weight;
        }
    }
    color /= weightSum;

    // Grayscale mix
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    vec3 grayscale = vec3(gray);
    color.rgb = mix(grayscale, color.rgb, u_var0);

    // Darken
    color.rgb *= 0.35;

    gl_FragColor = color;
}
