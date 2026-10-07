// UI Prismatic - fragment
// Lays the seven rainbow colors across the widget from left to right and scrolls
// them over time, so the whole gradient is visible at once and flows (same look
// as the tooltip name text). Used on the rarity "smoke" banner / sprite frame.
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;

varying vec2 v_TexCoord;

// How many full rainbows fit across the width (1.0 = one left-to-right sweep).
const float FREQ = 1.0;
// Scroll speed (rainbows per second).
const float SPEED = 0.15;

// HSV hue -> RGB (h in 0..1), smooth rainbow sweep.
vec3 hue2rgb(float h) {
    h = fract(h);
    return clamp(vec3(
        abs(h * 6.0 - 3.0) - 1.0,
        2.0 - abs(h * 6.0 - 2.0),
        2.0 - abs(h * 6.0 - 4.0)
    ), 0.0, 1.0);
}

void main()
{
    vec4 tex = texture2D(u_Tex0, v_TexCoord);

    // v_TexCoord is 0..1 across the image; use its X as the left-to-right position
    // and scroll with time -> the full rainbow is visible at once and flows.
    float hue = fract(v_TexCoord.x * FREQ - u_Time * SPEED);
    vec3 rainbow = hue2rgb(hue);

    // Tint the widget's image (keeps its alpha/shape, e.g. the smoke texture).
    gl_FragColor = vec4(tex.rgb * rainbow, tex.a) * u_Color;
}
