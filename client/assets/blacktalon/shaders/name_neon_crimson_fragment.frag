// Name Neon (Crimson Eclipse) - BLACK <-> RED.
// The ramp between the two is smooth and slow, but the palette only ever holds
// TWO colours: pure black and full-saturation neon red. What made an earlier
// version read as a dull dark red was not the gradient itself, it was a
// desaturated dark-red stop parked in the middle of the cycle plus an ember
// core lifting the black half. Both are gone: the mid tones here are just a
// dimmer pure red, and the hot core is gated by the band so the black stays
// black.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3 VOID_BLACK = vec3(0.02, 0.01, 0.01);
const vec3 NEON_RED   = vec3(1.00, 0.06, 0.05);
const vec3 CORE_EMBER = vec3(1.00, 0.35, 0.20); // hot core, only on red bands

const float CYCLE_SPEED = 0.9;  // slower drift, so it reads as a sweep
const float BAND_FREQ   = 2.2;  // wider bands = longer, softer transitions
const float GLOW        = 1.25;
// How fast the black->red ramp happens. A WIDE window (near 0.0/1.0) is a soft
// gradient; narrowing it toward 0.5 makes the edge hard and starts to strobe.
const float EDGE_LO     = 0.05;
const float EDGE_HI     = 0.95;
// Faint red floor on the glyph core so the name never fully disappears while
// the black band is over it. Lower this to 0.0 for pure black.
const float BLACK_FLOOR = 0.10;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Travelling wave, then snapped so the mid tones pass by quickly.
    float phase = v_TexCoord.x * BAND_FREQ + time * CYCLE_SPEED;
    float wave  = sin(phase) * 0.5 + 0.5;
    float band  = smoothstep(EDGE_LO, EDGE_HI, wave);

    vec3 color = mix(VOID_BLACK, NEON_RED, band);

    // Breathing glow + flicker applied only to the lit half -- multiplying the
    // black half by these does nothing visible anyway, but gating keeps the
    // black from picking up any brightness at the band edges.
    float pulse   = sin(time * 4.0) * 0.15 + 0.85;
    float flicker = sin(time * 20.0 + v_TexCoord.x * 30.0) * 0.05 + 0.95;
    color *= mix(1.0, GLOW * pulse * flicker, band);

    // Ember core, gated by the band: red letters glow, black letters do not.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float coreIntensity = pow(luminance, 0.5);
    color = mix(color, CORE_EMBER, coreIntensity * 0.30 * band);

    // Readability floor for the black phase: a barely-lit dark red glyph.
    color = max(color, vec3(BLACK_FLOOR, 0.015, 0.02) * coreIntensity);

    color *= (luminance * 0.2 + 0.8);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, texColor.a);
}
