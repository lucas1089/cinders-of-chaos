varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;

// Light color tint + exposure-style highlight boost + shadow crush. Keeps the
// creature's original colors visible, blends the new color on top, emphasizes
// the lighter pixels and deepens the dark pixels toward black (no animation).
const float TINT_MIX     = 0.4;   // 0 = only original, 1 = fully recolored
const float EXPOSURE     = 1.0;   // highlight boost strength (exposure-like)
const float SHADOW_CRUSH = 0.25;  // higher = more pixels pushed toward black

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Keep transparent pixels transparent (preserve the sprite silhouette).
    if (texColor.a < 0.01) discard;

    vec3 tint = vec3(0.1, 0.2, 0.9); // dark blue

    float luma = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));

    // Blend the original sprite color toward the new color only partway, so
    // BOTH the original creature colors and the new color stay visible.
    vec3 recolor = tint * (luma * 0.6 + 0.4);
    vec3 blended = mix(texColor.rgb, recolor, TINT_MIX);

    // Exposure: boost grows with brightness, so the light colors pop.
    float highlight = smoothstep(0.35, 1.0, luma);
    vec3 exposed = blended * (1.0 + highlight * EXPOSURE);

    // Shadow crush: ramp from black at luma 0 up to full at SHADOW_CRUSH, so the
    // darkest pixels go black while everything above stays untouched.
    float shadow = smoothstep(0.0, SHADOW_CRUSH, luma);

    gl_FragColor = vec4(exposed * shadow, texColor.a);
}
