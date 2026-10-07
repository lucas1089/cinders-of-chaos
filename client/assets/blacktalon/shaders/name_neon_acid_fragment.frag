// Name Neon (Acid Bloom) - Neon-Glow-style effect restricted to SHOCK GREEN
// <-> HOT PINK. Both transitions run through a pale mint bridge: a direct
// green->pink RGB lerp passes through olive grey, which kills the neon look.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3 SHOCK_GREEN = vec3(0.25, 1.00, 0.35);
const vec3 PALE_MINT   = vec3(0.80, 1.00, 0.88); // bright bridge green <-> pink
const vec3 HOT_PINK    = vec3(1.00, 0.18, 0.70);
const vec3 CORE_WHITE  = vec3(1.00, 0.95, 1.00);

const float CYCLE_SPEED = 1.5;
const float BAND_FREQ   = 3.0;
const float GLOW        = 1.2;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    float phase = v_TexCoord.x * BAND_FREQ + time * CYCLE_SPEED;
    float cyclePhase = fract(phase / 6.283185);

    // Symmetric loop: green -> mint -> pink -> mint -> green.
    vec3 color;
    if (cyclePhase < 0.25) {
        color = mix(SHOCK_GREEN, PALE_MINT, cyclePhase * 4.0);
    } else if (cyclePhase < 0.5) {
        color = mix(PALE_MINT, HOT_PINK, (cyclePhase - 0.25) * 4.0);
    } else if (cyclePhase < 0.75) {
        color = mix(HOT_PINK, PALE_MINT, (cyclePhase - 0.5) * 4.0);
    } else {
        color = mix(PALE_MINT, SHOCK_GREEN, (cyclePhase - 0.75) * 4.0);
    }

    float pulse   = sin(time * 4.0) * 0.15 + 0.85;
    float flicker = sin(time * 20.0 + v_TexCoord.x * 30.0) * 0.05 + 0.95;
    color *= GLOW * pulse * flicker;

    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float coreIntensity = pow(luminance, 0.5);
    color = mix(color, CORE_WHITE, coreIntensity * 0.25);

    color *= (luminance * 0.2 + 0.8);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, texColor.a);
}
