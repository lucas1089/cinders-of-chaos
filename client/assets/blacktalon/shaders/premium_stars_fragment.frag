// Premium celebration: tiny golden stars drifting slowly from the bottom to the
// top of the widget, twinkling as they rise. Same proven pattern as the inferno
// ui_fire_overlay image-shader: v_TexCoord for coords, u_Time for animation and
// u_var0 as the master opacity driven from Lua (defaults to 0 = invisible).

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;   // widget image (opaque; only used to gate alpha)
uniform float u_Time;
uniform float u_var0;       // master opacity 0..1

// Battle Pass window aspect so the star cells stay square-ish.
const float ASPECT = 1120.0 / 615.0;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 4-pointed sparkle: a small bright core plus thin rays along the axes (and
// fainter diagonal rays), instead of a plain round dot.
float starShape(vec2 p, float size, float flare)
{
    float d = length(p);

    // Small solid core.
    float m = smoothstep(size, 0.0, d);

    // Main cross rays (thin along the x/y axes, fading with distance).
    float rays = max(0.0, 1.0 - abs(p.x * p.y) * 500.0);
    rays = pow(rays, 3.0) * smoothstep(size * 7.0, 0.0, d);
    m += rays * flare;

    // Fainter diagonal rays for extra sparkle.
    vec2 q = vec2(p.x - p.y, p.x + p.y) * 0.7071;
    float rays2 = max(0.0, 1.0 - abs(q.x * q.y) * 900.0);
    rays2 = pow(rays2, 3.0) * smoothstep(size * 4.5, 0.0, d);
    m += rays2 * flare * 0.5;

    return m;
}

// One layer of rising stars: the field scrolls down in sample space, which moves
// the stars UP on screen (v_TexCoord.y = 0 is the top).
float starLayer(vec2 uv, float cells, float speed, float size)
{
    vec2 guv = uv;
    guv.y += u_Time * speed;              // rise slowly

    vec2 cell = floor(guv * cells);
    vec2 f = fract(guv * cells);

    float rnd = hash(cell);
    if (rnd < 0.55)                        // most cells stay empty (sparse field)
        return 0.0;

    vec2 starPos = vec2(hash(cell + 1.3), hash(cell + 2.7)) * 0.5 + 0.25;

    // Twinkle: each star blinks at its own pace and phase; the flare (ray length)
    // twinkles harder than the core so the sparkle really glints.
    float tw = 0.45 + 0.55 * sin(u_Time * (1.5 + rnd * 2.5) + rnd * 6.2831);

    return starShape(f - starPos, size * (0.7 + rnd * 0.6), tw) * (0.35 + 0.65 * tw);
}

void main()
{
    vec4 tex = texture2D(u_Tex0, v_TexCoord);

    vec2 uv = v_TexCoord;
    uv.x *= ASPECT;

    // Two layers: small/slow far stars + slightly bigger/faster near stars.
    float s = starLayer(uv, 14.0, 0.045, 0.045);
    s += starLayer(uv + 3.7, 9.0, 0.075, 0.065) * 1.2;

    vec3 gold       = vec3(1.0, 0.86, 0.45);
    vec3 brightGold = vec3(1.0, 0.97, 0.82);
    vec3 color = mix(gold, brightGold, clamp(s, 0.0, 1.0));

    float alpha = clamp(s, 0.0, 1.0) * u_var0 * tex.a;
    gl_FragColor = vec4(color, alpha);
}
