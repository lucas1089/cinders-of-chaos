// Rarity glow fragment shader (BlackTalon tooltip rarity-style system).
//
// OUTER glow: the glow widget is larger than the panel and drawn BEHIND it, so
// only the ring that sticks out around the panel is visible. The glow is
// brightest at the panel edge and fades OUTWARD to nothing at the widget edge,
// giving a soft colored halo around the tooltip. The region over the panel
// saturates but is hidden behind the opaque panel.
//
// Color comes from the widget background color (u_Color), so a SINGLE shader
// serves every rarity -- item_tooltip.lua calls setBackgroundColor() with the
// rarity color (and cycles it for Divine). The glow breathes via u_Time. The
// sampled texture is ignored on purpose (pure UV math), so no image is needed.
precision mediump float;

uniform vec4 u_Color;
uniform float u_Time;
varying vec2 v_TexCoord;

void main()
{
    vec2 uv = v_TexCoord;

    // Distance to the nearest edge in UV space (0 at the widget edge = outer
    // rim of the halo, larger toward the center = under the panel).
    float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));

    // 0 at the outer rim, rising to full by the time it reaches the panel edge,
    // so the halo is brightest hugging the panel and fades outward.
    float band = 0.075;
    float glow = smoothstep(0.0, band, d);
    glow = pow(glow, 1.2);

    // Gentle breathing so the halo feels alive.
    float pulse = 0.72 + 0.28 * sin(u_Time * 3.0);

    // Energy flowing around the halo (diagonal travelling wave), echoing the
    // animated outline glow on the item sprite itself.
    float flow = 0.78 + 0.22 * sin((uv.x + uv.y) * 12.0 - u_Time * 4.0);

    float alpha = glow * pulse * flow * u_Color.a;
    if (alpha < 0.004) discard;

    gl_FragColor = vec4(u_Color.rgb, alpha);
}
