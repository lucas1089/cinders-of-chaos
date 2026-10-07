// Item sprite shader: a strong, steady glowing outline hugging the item's
// silhouette (inner rim). Uses the same edge detection as the transmute outline
// shaders, so it stays clean on atlas sprites -- transparent pixels are
// discarded, and neighbouring atlas sprites can only REDUCE the rim, never
// create a false outline. Applied to Legendary+ items in
// modules/gamelib/ui/uiitem.lua.
uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;

const float ALPHA_THRESHOLD = 0.01;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    float alpha = texColor.a;

    // Only shade the sprite itself; keeps the silhouette and avoids bleeding.
    if (alpha < ALPHA_THRESHOLD)
        discard;

    vec2 texel = vec2(1.0 / 64.0);
    if (u_Resolution.x > 0.0 && u_Resolution.y > 0.0) {
        texel = vec2(1.0 / u_Resolution.x, 1.0 / u_Resolution.y);
    }

    // Average alpha of the 8 neighbours; low near the edge, ~1 deep inside.
    float nearAvg =
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x, -texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x, -texel.y)).a;
    nearAvg /= 8.0;

    // Rim factor: strong where the sprite meets transparency (the outline).
    // Higher multiplier -> thicker, more pronounced outline.
    float rim = clamp((1.0 - nearAvg) * 2.4, 0.0, 1.0);

    // Steady, strong glow (no pulsing) -- always fully visible.
    vec3 glow = vec3(1.0, 0.84, 0.32);   // warm gold
    vec3 finalColor = texColor.rgb + glow * rim * 1.8;

    gl_FragColor = vec4(finalColor, alpha);
}
