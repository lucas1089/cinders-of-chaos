// Divine Diagonal Sweep - a warm amber shine streak crossing the text
// LEFT -> RIGHT at a diagonal tilt (classic "card shine").
// BlackTalon MMORPG.
//
// Text-shader interface: v_TexCoord = per-glyph font-atlas coord (glyph sample),
// u_Tex0 = font texture, u_Time. v_LocalPos = text-local pixel position from
// name_sweep_vertex: x = 0..lineWidth (across the whole line, shared by all
// glyphs), y = 0 top .. ~lineHeight bottom. Using v_LocalPos (not v_TexCoord,
// which is per-glyph atlas coords) is what makes the sweep travel uniformly
// across the line instead of jumping per-letter.
//
// The line WIDTH is not known in the shader (varies per message), so the streak
// sweeps in PIXEL space over a fixed range that covers the broadcast widths; the
// tilt comes from mixing y into the diagonal coordinate. Every additive term is
// gated by a "solid interior" mask so the glow never spills past the edges.

varying vec2 v_TexCoord;
varying vec2 v_LocalPos;
uniform sampler2D u_Tex0;
uniform float u_Time;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only process visible glyph pixels
    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Solid-interior mask: 0 at anti-aliased edges, 1 well inside the stroke.
    float solid = smoothstep(0.4, 0.85, texColor.a);

    // Yellow text, white shine
    vec3 baseCol  = vec3(1.00, 0.82, 0.15); // yellow (un-lit text)
    vec3 sweepCol = vec3(1.00, 1.00, 1.00); // white (streak peak)

    // Diagonal coordinate: x mixed with y so the band is tilted. y spans only
    // ~0..12px, so amplify it (SLOPE) to make the tilt clearly diagonal across
    // the line height. Streak center sweeps in pixels from left of the line to
    // past a typical broadcast width, moving LEFT -> RIGHT.
    float SLOPE = 3.0;
    float d = v_LocalPos.x + (12.0 - v_LocalPos.y) * SLOPE; // "/" tilt
    float p = mix(-60.0, 520.0, fract(time * 0.4));         // sweep position (px)
    float band = smoothstep(55.0, 0.0, abs(d - p));         // ~55px WIDE soft streak
    band = pow(band, 1.5);

    // Yellow base fills the whole glyph; the streak brightens toward white,
    // strictly inside the stroke (gated by solid).
    vec3 col = baseCol;
    col = mix(col, sweepCol, band * solid);
    col += vec3(0.30, 0.30, 0.30) * band * solid; // extra white glow at the streak

    // The "rounded" font bakes a BLACK outline into the atlas (fill = white,
    // outline = black). Keep the outline intact: the atlas luminance is a
    // fill/outline mask - the shader color paints ONLY the bright fill, while
    // the dark outline keeps its original (black) color. This mirrors how the
    // normal text render leaves the outline black (black * color = black), and
    // works for plain fonts too (no baked outline -> luminance ~1 everywhere).
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float fillMask = smoothstep(0.25, 0.6, luminance);
    vec3 finalColor = mix(texColor.rgb, col, fillMask);
    finalColor = clamp(finalColor, 0.0, 1.15);

    gl_FragColor = vec4(finalColor, texColor.a);
}
