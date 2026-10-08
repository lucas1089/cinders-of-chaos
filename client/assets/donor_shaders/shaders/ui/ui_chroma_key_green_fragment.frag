// Green-screen chroma key for UIVideo (or any image widget).
// Pixels where green dominates over red+blue become transparent, so a fire (or
// any subject) shot on a green background can be overlaid cleanly. MP4/H.264
// can't carry alpha, so we key the green at render time instead.
//
// u_var0 acts as a MASTER OPACITY (0..1): drive it from Lua (setImageShaderVar)
// to fade the whole overlay in/out with the inferno heat buildup. Defaults to 1.

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_var0;   // master opacity, default 1

// Tunables -----------------------------------------------------------------
// Greenness = g - max(r, b). Pure green (#00FF00) -> 1.0; fire (orange/red) -> negative.
const float KEY_LO  = 0.10;   // below this greenness = fully opaque (kept)
const float KEY_HI  = 0.35;   // above this greenness = fully transparent (keyed)
const float SPILL   = 0.50;   // how strongly to suppress green spill on kept edges

void main()
{
    vec4 c = texture2D(u_Tex0, v_TexCoord);

    float greenness = c.g - max(c.r, c.b);
    float key = smoothstep(KEY_LO, KEY_HI, greenness);   // 1 = green -> transparent

    // Spill suppression: on edge/halo pixels pull the green channel down toward
    // the neighbouring red/blue so leftover green fringing disappears.
    float spill = max(greenness, 0.0);
    c.g -= spill * SPILL;

    float alpha = (1.0 - key) * c.a * clamp(u_var0, 0.0, 1.0);
    gl_FragColor = vec4(c.rgb, alpha);
}
