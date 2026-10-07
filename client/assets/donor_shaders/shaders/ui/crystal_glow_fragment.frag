// crystal_glow — single tinted pulsing-glow shader for the Crystal Tree.
// Cloned from ui_legendary but the hue is driven ENTIRELY by u_Color (the
// widget's image-color / setColor), so ONE registered shader serves all 7
// branch colors. White/greyscale sprites are tinted by u_Color and then
// pulse in brightness over time, giving the "pulsing colored node glow"
// look from the mockup.
//
// To make a node brighter/keystone vs. a dim available node, just vary the
// widget color alpha or use a brighter image-color at the call site.
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;
uniform vec4 u_Color;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;
varying vec2 v_Position;

void main()
{
    vec4 textureColor = texture2D(u_Tex0, v_TexCoord);

    // Pulse the brightness over time (0.70 .. 1.30). Same cadence as
    // ui_legendary so it visually matches the rest of the UI.
    float pulse = 0.85 + 0.30 * sin(u_Time * 2.0);

    // Multiply the (white/greyscale) sprite by the pulse, then let u_Color
    // supply the actual hue + alpha. Because the sprite is white, the final
    // color == u_Color * pulse on opaque pixels.
    vec3 rgb = textureColor.rgb * pulse;
    vec4 finalColor = vec4(rgb, textureColor.a);

    gl_FragColor = finalColor * u_Color;
}
