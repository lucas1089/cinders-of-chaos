// Name Neon (Deep Frost) - Neon-Glow-style effect restricted to DEEP NAVY
// <-> BABY BLUE. Both stops sit in the blue family, so the blend is a straight
// ramp through a mid azure; no bridge hue is needed here.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3 DEEP_NAVY  = vec3(0.04, 0.10, 0.45);
const vec3 MID_AZURE  = vec3(0.20, 0.50, 0.95);
const vec3 BABY_BLUE  = vec3(0.68, 0.90, 1.00);
const vec3 CORE_ICE   = vec3(0.90, 0.97, 1.00); // pale icy core, still blue

const float CYCLE_SPEED = 1.4;
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

    // Symmetric loop: navy -> azure -> baby blue -> azure -> navy.
    vec3 color;
    if (cyclePhase < 0.25) {
        color = mix(DEEP_NAVY, MID_AZURE, cyclePhase * 4.0);
    } else if (cyclePhase < 0.5) {
        color = mix(MID_AZURE, BABY_BLUE, (cyclePhase - 0.25) * 4.0);
    } else if (cyclePhase < 0.75) {
        color = mix(BABY_BLUE, MID_AZURE, (cyclePhase - 0.5) * 4.0);
    } else {
        color = mix(MID_AZURE, DEEP_NAVY, (cyclePhase - 0.75) * 4.0);
    }

    float pulse   = sin(time * 4.0) * 0.15 + 0.85;
    float flicker = sin(time * 20.0 + v_TexCoord.x * 30.0) * 0.05 + 0.95;
    color *= GLOW * pulse * flicker;

    // The navy end is dark, so lift the glyph core a bit harder than the other
    // neon variants -- otherwise the name goes unreadable on dark ground.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float coreIntensity = pow(luminance, 0.5);
    color = mix(color, CORE_ICE, coreIntensity * 0.35);

    color *= (luminance * 0.2 + 0.8);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, texColor.a);
}
