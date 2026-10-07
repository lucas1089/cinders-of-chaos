// Name Pulse Rainbow (per-letter) - each LETTER is one rainbow color, the 7
// colors run in order along the name (1>2>3...7>1) and flow smoothly over time,
// with a soft blend between colors for a natural look. NO motion, NO outline.
// Edges are handled EXACTLY like the "Rainbow" and "Neon Glow" name shaders:
// modulate by the glyph's own luminance and keep the original alpha, so the
// font's built-in edge/shadow stays intact and readable.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
varying vec2 v_LocalPos;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Width (text-local px) of one color cell. Proportional font -> approximate.
// If a letter shows two colors, raise it; if letters share a color, lower it.
const float LETTER_WIDTH = 8.0;

// Rainbow flow speed along the name (continuous -> smooth). Set to 0.0 for a
// completely static rainbow.
const float FLOW_SPEED = 0.45;

// Blend between one letter's color and the next. 0.0 = hard edges; ~0.5 = soft
// natural transition; 1.0 = fully continuous gradient (no solid center left).
const float BLEND = 0.55;

// Standard smooth hue wheel (0..1 -> full rainbow, in order).
vec3 hue2rgb(float h)
{
    h = fract(h);
    float r = abs(h * 6.0 - 3.0) - 1.0;
    float g = 2.0 - abs(h * 6.0 - 2.0);
    float b = 2.0 - abs(h * 6.0 - 4.0);
    return clamp(vec3(r, g, b), 0.0, 1.0);
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only paint visible glyph pixels; keep the font's antialiased edges.
    if (texColor.a < 0.01) {
        discard;
    }

    // Per-letter cell, with a soft ramp into the next cell's hue near the edge
    // (BLEND-wide) so colors transition naturally instead of stepping hard.
    float p = v_LocalPos.x / LETTER_WIDTH;
    float band = floor(p) + smoothstep(1.0 - BLEND, 1.0, fract(p));

    // Adjacent cells 1/7 of the wheel apart -> 7 rainbow colors across 7 letters,
    // in order. '- u_Time' scrolls left->right smoothly (use '+' to reverse).
    float hue = band * (1.0 / 7.0) - u_Time * FLOW_SPEED;
    vec3 rainbow = hue2rgb(hue);

    // Same edge treatment as the Rainbow/Neon shaders: keep the glyph's shading
    // (bright core, darker antialiased edge) and its original alpha.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = rainbow * (luminance * 0.5 + 0.5);

    gl_FragColor = vec4(finalColor, texColor.a);
}
