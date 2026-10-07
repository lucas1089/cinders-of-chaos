uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_Position;
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec2 u_Resolution;
uniform float u_spriteSize;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    if (texColor.a < 0.01) discard;

    // Fast pulsing red overlay — blinks between normal and full red
    // sin() oscillates 0..1 at ~4Hz for urgent feel
    float pulse = 0.5 + 0.5 * sin(u_Time * 25.0);

    // Blend towards red: at pulse=1 sprite is fully red, at pulse=0 normal
    vec3 red = vec3(1.0, 0.0, 0.0);
    vec3 blended = mix(texColor.rgb, red, pulse * 0.85);

    gl_FragColor = vec4(blended, texColor.a);
}
