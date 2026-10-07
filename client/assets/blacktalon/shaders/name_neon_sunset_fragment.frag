// Name Neon (Sunset) - the same Neon-Glow-style effect as name_neon_fragment,
// but restricted to a two-tone ORANGE <-> PURPLE palette (basketball "Lakers"
// look). The two hues are bridged through a hot magenta stop so the cycle never
// crosses through mud/brown the way a straight orange->purple RGB lerp does.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Two-tone palette + the magenta bridge that keeps the blend neon.
const vec3 DEEP_PURPLE  = vec3(0.38, 0.10, 0.85);
const vec3 BRIGHT_PURPLE= vec3(0.62, 0.30, 1.00);
const vec3 HOT_MAGENTA  = vec3(0.95, 0.30, 0.70); // bridge purple <-> orange
const vec3 NEON_ORANGE  = vec3(1.00, 0.45, 0.05);
const vec3 CORE_AMBER   = vec3(1.00, 0.88, 0.70); // warm bright core

const float CYCLE_SPEED = 1.5;  // travelling colour cycle along the text
const float BAND_FREQ   = 3.0;  // how many colour bands fit across the name
const float GLOW        = 1.2;  // overall neon brightness boost

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Only process visible text pixels
    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Colour cycling that also travels horizontally across the name.
    float phase = v_TexCoord.x * BAND_FREQ + time * CYCLE_SPEED;
    float cyclePhase = fract(phase / 6.283185);

    // Symmetric loop: purple -> magenta -> orange -> magenta -> purple, so the
    // return leg never takes the direct orange->purple path through mud, and
    // the cycle closes on the same colour it started from (no visible jump).
    vec3 color;
    if (cyclePhase < 0.2) {
        color = mix(DEEP_PURPLE, BRIGHT_PURPLE, cyclePhase * 5.0);
    } else if (cyclePhase < 0.4) {
        color = mix(BRIGHT_PURPLE, HOT_MAGENTA, (cyclePhase - 0.2) * 5.0);
    } else if (cyclePhase < 0.6) {
        color = mix(HOT_MAGENTA, NEON_ORANGE, (cyclePhase - 0.4) * 5.0);
    } else if (cyclePhase < 0.8) {
        color = mix(NEON_ORANGE, HOT_MAGENTA, (cyclePhase - 0.6) * 5.0);
    } else {
        color = mix(HOT_MAGENTA, DEEP_PURPLE, (cyclePhase - 0.8) * 5.0);
    }

    // Breathing glow + subtle electric flicker (same feel as "Neon Glow").
    float pulse   = sin(time * 4.0) * 0.15 + 0.85;
    float flicker = sin(time * 20.0 + v_TexCoord.x * 30.0) * 0.05 + 0.95;
    color *= GLOW * pulse * flicker;

    // Warm amber core instead of pure white, so the glow stays inside the
    // orange/purple family.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float coreIntensity = pow(luminance, 0.5);
    color = mix(color, CORE_AMBER, coreIntensity * 0.28);

    // Preserve a bit of the glyph shading and keep the original alpha.
    color *= (luminance * 0.2 + 0.8);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, texColor.a);
}
