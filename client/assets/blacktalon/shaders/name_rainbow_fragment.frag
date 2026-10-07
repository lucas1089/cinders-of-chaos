// Name Rainbow Shader - Cycling rainbow colors for text rendering
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only process visible text pixels
    if (texColor.a < 0.01) {
        discard;
    }

    // Create cycling rainbow effect based on position and time
    // Using sine waves with phase offsets for RGB channels
    float speed = 3.0;
    float frequency = 8.0;
    float timeOffset = mod(u_Time, 3600.0) * speed;

    // Calculate rainbow colors with horizontal position influence
    float phase = v_TexCoord.x * frequency + timeOffset;

    vec3 rainbow;
    rainbow.r = sin(phase + 0.0) * 0.5 + 0.5;
    rainbow.g = sin(phase + 2.094) * 0.5 + 0.5;  // 2*PI/3 offset
    rainbow.b = sin(phase + 4.189) * 0.5 + 0.5;  // 4*PI/3 offset

    // Ensure colors are vibrant by boosting saturation
    float brightness = max(rainbow.r, max(rainbow.g, rainbow.b));
    rainbow = mix(rainbow, rainbow / brightness, 0.3);

    // Apply rainbow color to text while preserving luminance variations
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = rainbow * (luminance * 0.5 + 0.5);

    gl_FragColor = vec4(finalColor, texColor.a);
}
