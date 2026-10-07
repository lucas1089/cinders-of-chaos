// Name Rainbow (Arcane Prism) - the Rainbow name shader with the spectrum cut
// down to three stops: GREEN -> YELLOW -> PURPLE, looping. Like the original
// Rainbow it travels horizontally across the text and re-saturates the result,
// which is what keeps the yellow->purple and purple->green midpoints from
// washing out to grey.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3 ARCANE_GREEN  = vec3(0.20, 1.00, 0.30);
const vec3 ARCANE_YELLOW = vec3(1.00, 0.90, 0.15);
const vec3 ARCANE_PURPLE = vec3(0.60, 0.18, 1.00);

const float SPEED     = 1.6;
const float FREQUENCY = 4.0;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only process visible text pixels
    if (texColor.a < 0.01) {
        discard;
    }

    float timeOffset = mod(u_Time, 3600.0) * SPEED;
    float phase = v_TexCoord.x * FREQUENCY + timeOffset;
    float t = fract(phase / 6.283185);

    // Three equal thirds so no colour dominates the loop.
    vec3 prism;
    if (t < 0.333333) {
        prism = mix(ARCANE_GREEN, ARCANE_YELLOW, t * 3.0);
    } else if (t < 0.666667) {
        prism = mix(ARCANE_YELLOW, ARCANE_PURPLE, (t - 0.333333) * 3.0);
    } else {
        prism = mix(ARCANE_PURPLE, ARCANE_GREEN, (t - 0.666667) * 3.0);
    }

    // Push saturation back up (same trick as name_rainbow_fragment, but
    // stronger): the in-between shades of a 3-stop loop are the muddy ones.
    float brightness = max(prism.r, max(prism.g, prism.b));
    prism = mix(prism, prism / max(brightness, 0.001), 0.75);

    // Apply to the text while preserving its luminance variations.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 finalColor = prism * (luminance * 0.5 + 0.5);

    gl_FragColor = vec4(clamp(finalColor, 0.0, 1.0), texColor.a);
}
