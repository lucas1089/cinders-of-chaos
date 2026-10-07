// Name Blood Shader - forces the name to BLACK and runs blood down only some
// vertical channels (as if it dripped from the top of the name), pooling along
// the bottom edge so it connects with the falling drops rendered below.
// BlackTalon MMORPG.
//
// The letters used to keep their natural colour (green for most players), which
// clashed with the blood; they are now painted with the same near-black used by
// Crimson Eclipse, including its faint red floor so the name does not vanish on
// dark ground.
//
// Uses name_sweep_vertex, which exposes v_LocalPos = text-local pixel position
// (x across the whole name, y = 0 top .. ~lineHeight bottom). v_TexCoord is the
// per-glyph atlas coord used only to sample the font. u_Color = the name's own
// colour (kept as the base); u_Time drives the flow.
//
// The verdana-11px-rounded font bakes a BLACK outline into the atlas (fill =
// bright, outline = black). We recolour ONLY the bright fill (luminance mask) so
// the outline stays intact.

varying vec2 v_TexCoord;
varying vec2 v_LocalPos;
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;

// Letter colour, matched to name_neon_crimson_fragment's black phase.
const vec3  VOID_BLACK  = vec3(0.02, 0.01, 0.01);
// Faint red lift on the glyph fill so the name stays legible on dark tiles.
// Set to 0.0 for pure black.
const float BLACK_FLOOR = 0.10;

float hash(float n)
{
    return fract(sin(n) * 43758.5453123);
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    if (texColor.a < 0.01) {
        discard;
    }

    float time = mod(u_Time, 3600.0);

    // Preserve the baked black outline: only recolour the bright fill.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float fillMask = smoothstep(0.25, 0.6, luminance);

    // Base = black letters. Only the bright fill is repainted, so the atlas'
    // baked outline (fillMask ~ 0 there) and its antialiasing ramp survive.
    float coreIntensity = pow(luminance, 0.5);
    vec3 letter = max(VOID_BLACK, vec3(BLACK_FLOOR, 0.015, 0.02) * coreIntensity);
    vec3 base = mix(texColor.rgb * u_Color.rgb, letter, fillMask);

    // Text-local geometry (pixels).
    float x = v_LocalPos.x;
    float y = v_LocalPos.y;
    float LINE_H = 17.0;                 // approx scaled line height (tweak)
    float ny = clamp(y / LINE_H, 0.0, 1.0);

    // Blood palette.
    vec3 blood  = vec3(0.50, 0.02, 0.02);
    vec3 dark   = vec3(0.24, 0.00, 0.00);
    vec3 bright = vec3(0.90, 0.12, 0.08);

    // Vertical channels along the whole name; only some carry blood.
    float CH_W = 9.0;                    // px spacing between potential streaks
    float ch = floor(x / CH_W);
    float rnd = hash(ch + 3.7);
    float isBlood = step(0.5, rnd);      // ~half the channels drip

    // Thin streak centered in its channel.
    float within = fract(x / CH_W);
    float streak = smoothstep(0.42, 0.10, abs(within - 0.5));

    // Running front: blood flows from the top down to 'reach' (animated), while
    // leaving a faint permanent trickle behind it.
    float speed = 0.10 + hash(ch + 1.1) * 0.12;
    float reach = mix(0.30, 1.05, fract(time * speed + rnd * 7.0));
    float runMask = smoothstep(reach, reach - 0.18, ny); // 1 above the front
    float trickle = streak * (0.25 + 0.75 * runMask);

    // A denser source blob at the very top of each streak.
    float source = streak * smoothstep(0.22, 0.0, ny);

    // Pool at the base of the SAME streak (so the falling drop, which spawns on
    // this exact channel, appears to come straight out of the running blood).
    float pool = streak * smoothstep(0.84, 1.0, ny) * 0.9;

    float streakBlood = max(max(trickle, source), pool) * isBlood;
    float bloodAmt = clamp(streakBlood, 0.0, 1.0);

    // Wet bright bead riding the running front.
    float bead = streak * isBlood * smoothstep(0.07, 0.0, abs(ny - min(reach, 1.0)));

    // Blood colour: darker up high, brighter at the running front / pool.
    vec3 bcol = mix(dark, blood, smoothstep(0.0, 0.45, ny));
    bcol = mix(bcol, bright, clamp(max(bead, pool), 0.0, 1.0) * 0.7);

    vec3 col = mix(base, bcol, bloodAmt * fillMask);

    gl_FragColor = vec4(col, texColor.a * u_Color.a);
}
