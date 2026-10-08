// Name Static (Purple Neon) - a Neon-Glow-style effect but pulsing between a
// LIGHT PURPLE and a DARK PURPLE only. Breathing glow + subtle flicker + a
// lavender core, like the Neon shader, but strictly in the violet family.
// (Pink is deliberately avoided: greens are kept high enough that no color ever
//  drifts to magenta/pink.)
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Purple palette (keep G reasonably high vs R so it never reads as pink).
const vec3  DARK_PURPLE  = vec3(0.22, 0.06, 0.42);
const vec3  LIGHT_PURPLE = vec3(0.66, 0.45, 1.00);
const vec3  CORE_LAVENDER= vec3(0.85, 0.75, 1.00); // bright core, still violet

const float PULSE_SPEED  = 3.0;   // breathing speed (dark<->light)
const float FLOW_SPEED   = 1.5;   // gentle travelling shimmer along the text
const float GLOW         = 1.15;  // overall neon brightness boost

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Breathing between dark and light purple...
    float pulse = sin(time * PULSE_SPEED) * 0.5 + 0.5;              // 0..1
    // ...plus a soft travelling shimmer so it isn't perfectly uniform.
    float flow  = sin(v_TexCoord.x * 4.0 + time * FLOW_SPEED) * 0.5 + 0.5;
    float t = mix(pulse, flow, 0.35);

    vec3 color = mix(DARK_PURPLE, LIGHT_PURPLE, t);

    // Neon breathing glow + subtle electric flicker.
    float glowPulse = sin(time * 4.0) * 0.12 + 0.9;
    float flicker   = sin(time * 18.0 + v_TexCoord.x * 25.0) * 0.04 + 0.96;
    color *= GLOW * glowPulse * flicker;

    // Bright lavender core for the glowy look (mixed lightly, stays violet).
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float coreIntensity = pow(luminance, 0.5);
    color = mix(color, CORE_LAVENDER, coreIntensity * 0.25);

    // Preserve the glyph's shading a little and keep the original alpha.
    color *= (luminance * 0.2 + 0.8);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, texColor.a);
}
