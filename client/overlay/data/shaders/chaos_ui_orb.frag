// Cinders of Chaos: liquid health / mana orb (game_shaderfx). The widget image is the orb's round mask (its alpha
// cuts the orb); image-color tints the liquid. u_Params: x = fill 0..1, y = slosh 0..1 (raised by Lua when the value
// changes, then eased back), z = phase offset (two orbs do not move together), w = 1 for a bright foam line.
// Own math: a layered sine surface, a small value-noise field for the swirl, a fake sphere normal for the shading.
uniform sampler2D u_Tex0;
uniform vec4 u_Color;
uniform vec4 u_Params;
uniform float u_Time;
varying vec2 v_TexCoord;

float cellHash(vec2 c)
{
    c = fract(c * vec2(0.2713, 0.4127) + vec2(0.11, 0.73));
    c += dot(c, c.yx + 23.17);
    return fract((c.x + 0.37) * (c.y + 0.61) * 47.3);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 s = f * f * (3.0 - 2.0 * f);
    float a = cellHash(i);
    float b = cellHash(i + vec2(1.0, 0.0));
    float c = cellHash(i + vec2(0.0, 1.0));
    float d = cellHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

// The noise grid is turned off the screen axes (value noise on an upright grid read as square blocks in the liquid,
// owner screenshot 2026-10-21); the second layer turns further, so the two grids never line up.
float swirl(vec2 p, float t)
{
    mat2 turn = mat2(0.8, -0.6, 0.6, 0.8);
    float n = valueNoise(turn * (p * 4.0) + vec2(0.0, t * 0.35));
    n += 0.5 * valueNoise(turn * (turn * (p * 9.0)) - vec2(t * 0.22, t * 0.5) + vec2(5.2, 1.3));
    return n / 1.5;
}

// Round bubbles rising: a square grid of cells moving up, about one cell in three holds a bubble at its own place and
// size, kept inside its cell, with a soft edge and a lighter rim. (The first bubbles were the peaks of a 22 x 14 value
// noise: upright rectangles that looked like enlarged pixels.)
float bubbles(vec2 uv, float t)
{
    vec2 p = vec2(uv.x * 11.0, uv.y * 11.0 + t * 1.3);
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float on = step(0.66, cellHash(cell + vec2(3.0, 5.0)));
    vec2 centre = vec2(0.3, 0.3) + 0.4 * vec2(cellHash(cell + vec2(7.0, 3.0)), cellHash(cell + vec2(1.0, 9.0)));
    float radius = 0.1 + 0.12 * cellHash(cell + vec2(4.0, 11.0));
    float d = length(f - centre);
    float body = 1.0 - smoothstep(radius - 0.1, radius, d);
    float rim = body * smoothstep(radius * 0.3, radius, d);
    return on * (0.45 * body + 0.55 * rim);
}

void main()
{
    vec4 mask = texture2D(u_Tex0, v_TexCoord);
    if (mask.a < 0.01)
        discard;
    float t = u_Time + u_Params.z * 7.0;
    vec2 uv = v_TexCoord;
    vec2 c = uv - vec2(0.5);
    float r = clamp(length(c) * 2.0, 0.0, 1.0);
    // a sphere seen from the front: the normal's z falls off to the rim
    float nz = sqrt(max(0.0, 1.0 - r * r));

    float fill = clamp(u_Params.x, 0.0, 1.0);
    float slosh = clamp(u_Params.y, 0.0, 1.0);
    float amp = 0.012 + 0.035 * slosh;
    float wave = sin(uv.x * 9.0 + t * 2.1) * amp
               + sin(uv.x * 17.0 - t * 3.3) * amp * 0.45
               + sin(uv.x * 4.0 + t * 0.9 + 1.7) * amp * 0.8;
    // at 0 or 1 the surface sits outside the orb, so an empty orb is empty and a full one full
    float level = 1.0 - mix(-0.04, 1.04, fill) + wave * step(0.001, fill) * step(fill, 0.999);
    float below = smoothstep(level - 0.006, level + 0.006, uv.y);

    vec3 tint = u_Color.rgb;
    float depth = clamp((uv.y - level) / max(0.05, 1.0 - level), 0.0, 1.0);
    float sw = swirl(uv + vec2(0.0, -t * 0.03), t);
    vec3 liquid = tint * (0.55 + 0.6 * sw) * (1.05 - 0.45 * depth);
    // small bubbles rising, lighter the nearer the surface
    liquid += mix(tint, vec3(1.0), 0.25) * bubbles(uv, t) * 0.5 * (1.0 - depth);
    // the surface line: a thin light band right under the level
    float foam = smoothstep(0.03, 0.0, abs(uv.y - level - 0.012));
    liquid = mix(liquid, mix(tint, vec3(1.0), 0.55), foam * (0.35 + 0.5 * u_Params.w) * below);

    vec3 glass = vec3(0.05, 0.045, 0.06) + tint * 0.06;
    vec3 col = mix(glass, liquid, below);
    // sphere shading, a darker rim and a soft highlight at the upper left
    col *= 0.45 + 0.55 * nz;
    float spec = smoothstep(0.24, 0.0, length(uv - vec2(0.36, 0.28)));
    col += vec3(1.0) * spec * 0.35;
    float rim = smoothstep(0.80, 1.0, r);
    col = mix(col, col * 0.35, rim);
    gl_FragColor = vec4(col, mask.a * u_Color.a);
}
