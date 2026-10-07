// Name Matrix Shader - Matrix-style green flicker with character brightness
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 36000.0);

    // Divide text into virtual "character cells" for individual flicker
    float cellWidth = 0.06;
    float cellIndex = floor(v_TexCoord.x / cellWidth);

    // Random brightness per cell, changing over time
    float flickerSpeed = 4.0;
    float flickerPhase = hash(vec2(cellIndex, floor(time * flickerSpeed)));
    float nextFlickerPhase = hash(vec2(cellIndex, floor(time * flickerSpeed) + 1.0));
    float flickerFrac = fract(time * flickerSpeed);
    float flicker = mix(flickerPhase, nextFlickerPhase, smoothstep(0.0, 1.0, flickerFrac));

    // Some cells "rain" - brighten from top to bottom
    float rainDrop = hash(vec2(cellIndex * 7.3, floor(time * 2.0)));
    float rainY = fract(time * 1.5 + hash(vec2(cellIndex, 0.0)));
    float isRaining = step(0.7, rainDrop);
    float rainBright = isRaining * (1.0 - smoothstep(0.0, 0.3, abs(v_TexCoord.y - rainY)));

    // Matrix green color palette
    vec3 darkGreen = vec3(0.0, 0.15, 0.0);
    vec3 green = vec3(0.0, 0.7, 0.1);
    vec3 brightGreen = vec3(0.3, 1.0, 0.3);
    vec3 whiteGreen = vec3(0.7, 1.0, 0.7);

    // Brightness combines flicker and rain
    float brightness = flicker * 0.6 + 0.2 + rainBright * 0.5;
    brightness = clamp(brightness, 0.0, 1.0);

    // Map brightness to color
    vec3 matrixColor;
    if (brightness < 0.3) {
        matrixColor = mix(darkGreen, green, brightness / 0.3);
    } else if (brightness < 0.7) {
        matrixColor = mix(green, brightGreen, (brightness - 0.3) / 0.4);
    } else {
        matrixColor = mix(brightGreen, whiteGreen, (brightness - 0.7) / 0.3);
    }

    // Apply to text
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = matrixColor * (luminance * 0.4 + 0.6);

    // Slight CRT phosphor glow
    float glow = sin(v_TexCoord.y * 60.0) * 0.03 + 0.97;
    finalColor *= glow;

    gl_FragColor = vec4(finalColor, texColor.a);
}
