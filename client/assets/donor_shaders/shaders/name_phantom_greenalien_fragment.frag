// Name Phantom (Alien Green) - the same Neon-Glow-style breathing effect as the
// purple Static shader, but pulsing between a TOXIC LIGHT GREEN and a DARK GREEN
// for a sickly alien glow. Breathing glow + subtle flicker + a pale green core.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Alien-green palette (kept in the green family so it never drifts elsewhere).
const vec3  DARK_GREEN  = vec3(0.04, 0.20, 0.06);
const vec3  LIGHT_GREEN = vec3(0.35, 1.00, 0.28);
const vec3  CORE_GREEN  = vec3(0.78, 1.00, 0.62); // bright core, still alien-green

const float PULSE_SPEED = 3.0;   // breathing speed (dark <-> light)
const float FLOW_SPEED  = 1.5;   // gentle travelling shimmer along the text
const float GLOW        = 1.15;  // overall neon brightness boost

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Breathing between dark and toxic green...
    float pulse = sin(time * PULSE_SPEED) * 0.5 + 0.5;
    // ...plus a soft travelling shimmer so it isn't perfectly uniform.
    float flow  = sin(v_TexCoord.x * 4.0 + time * FLOW_SPEED) * 0.5 + 0.5;
    float mixv = mix(pulse, flow, 0.35);

    vec3 color = mix(DARK_GREEN, LIGHT_GREEN, mixv);

    // Neon breathing glow + subtle electric flicker.
    float glowPulse = sin(time * 4.0) * 0.12 + 0.9;
    float flicker   = sin(time * 18.0 + v_TexCoord.x * 25.0) * 0.04 + 0.96;
    color *= GLOW * glowPulse * flicker;

    // Bright pale-green core for the glowy look.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float coreIntensity = pow(luminance, 0.5);
    color = mix(color, CORE_GREEN, coreIntensity * 0.25);

    color *= (luminance * 0.2 + 0.8);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, texColor.a);
}
