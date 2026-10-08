// Faint full-screen animated fire overlay, sampled from idler_fire.png.
// The dark background of the texture is keyed out by luminance (only the bright
// flames remain), the pattern scrolls over time so it looks alive, and u_var0
// is a master opacity driven from Lua (kept low for a subtle ambience).

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;   // the widget image (idler_fire.png)
uniform float u_Time;
uniform float u_var0;       // master opacity 0..1

// Tunables -----------------------------------------------------------------
const vec2  TILE        = vec2(2.0, 1.4);  // how many times the fire repeats on screen
const float SCROLL_UP   = 0.035;           // upward scroll speed (the fire "rises")
const float SCROLL_SIDE = 0.008;           // slight sideways drift
const float KEY_LO      = 0.18;            // luminance below this = transparent
const float KEY_HI      = 0.50;            // luminance above this = fully visible
const float FLICKER_AMT = 0.12;            // gentle brightness flicker

void main()
{
    // Two scrolled samples (offset in phase) cross-faded so the wrap seam of
    // the non-tileable texture never shows as a hard moving line.
    vec2 base = v_TexCoord * TILE;
    vec2 drift = vec2(u_Time * SCROLL_SIDE, -u_Time * SCROLL_UP);

    vec2 uvA = fract(base + drift);
    vec2 uvB = fract(base + drift + vec2(0.37, 0.5));
    vec3 a = texture2D(u_Tex0, uvA).rgb;
    vec3 b = texture2D(u_Tex0, uvB).rgb;

    // Tent weights that fall to zero at each layer's vertical wrap, hiding it.
    float wA = sin(fract(base.y + drift.y) * 3.14159265);
    float wB = sin(fract(base.y + drift.y + 0.5) * 3.14159265);
    vec3 fire = (a * wA + b * wB) / max(wA + wB, 0.001);

    float lum = dot(fire, vec3(0.299, 0.587, 0.114));
    float key = smoothstep(KEY_LO, KEY_HI, lum);   // bright fire kept, dark dropped

    // Gentle flicker so it breathes.
    float flicker = 1.0 - FLICKER_AMT + FLICKER_AMT * sin(u_Time * 3.0 + v_TexCoord.x * 8.0);

    float alpha = key * flicker * clamp(u_var0, 0.0, 1.0);
    gl_FragColor = vec4(fire, alpha);
}
