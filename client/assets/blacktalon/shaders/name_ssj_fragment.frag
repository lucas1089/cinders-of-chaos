// Name Super Saiyan Shader - the LETTERS themselves burn: animated fire flows up
// through the glyph shapes, white/gold hot at the base and cooling to orange/red
// toward the top. Flame tongues licking above the letters are a separate per-glyph
// canvas (name_ssj_flames), drawn by Creature::drawInformation.
// BlackTalon MMORPG.
//
// Uses name_sweep_vertex: v_TexCoord = per-glyph atlas coord (glyph sample),
// v_LocalPos = text-local pixel position (y = 0 top .. ~lineHeight bottom) used for
// the vertical heat gradient. u_Color = the name's own colour/alpha. The
// verdana-11px-rounded font bakes a BLACK outline; we recolour only the bright fill.

varying vec2 v_TexCoord;
varying vec2 v_LocalPos;
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p)
{
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p *= 2.02;
        a *= 0.5;
    }
    return v;
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    if (texColor.a < 0.01) {
        discard;
    }

    float t = mod(u_Time, 6000.0);

    // Preserve the baked black outline: recolour only the bright fill.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float fillMask = smoothstep(0.25, 0.6, luminance);

    // Vertical position within the name line (0 top .. 1 bottom).
    float LINE_H = 17.0;
    float ny = clamp(v_LocalPos.y / LINE_H, 0.0, 1.0);

    // Fire turbulence in text-local space, scrolling UP over time.
    vec2 fp = vec2(v_LocalPos.x * 0.17, v_LocalPos.y * 0.16 - t * 1.5);
    float n = fbm(fp);

    // Heat: hot at the base of the letters, plus turbulence; cooler at the tips.
    float heat = (1.0 - ny) * 0.55 + n * 0.75;
    heat = clamp(heat, 0.0, 1.0);

    vec3 red    = vec3(0.75, 0.05, 0.02);
    vec3 orange = vec3(1.00, 0.42, 0.05);
    vec3 gold   = vec3(1.00, 0.82, 0.15);
    vec3 white  = vec3(1.00, 0.98, 0.82);
    vec3 fire = mix(red, orange, smoothstep(0.15, 0.40, heat));
    fire = mix(fire, gold, smoothstep(0.40, 0.62, heat));
    fire = mix(fire, white, smoothstep(0.68, 0.88, heat));

    vec3 finalColor = mix(texColor.rgb, fire, fillMask);
    finalColor = clamp(finalColor, 0.0, 1.2);

    gl_FragColor = vec4(finalColor, texColor.a * u_Color.a);
}
