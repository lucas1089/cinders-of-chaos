// Gale / Wind (EXTENDED) - white & gray air currents streaming around the body.
//   - Body: desaturated (color blown out) + faint streaks passing over it + a
//     bright windward rim.
//   - WIND STREAKS: thin curved speed-lines made from noise stretched along the
//     flow direction and scrolled, so they read as fast-moving air. They swirl
//     around and off the character into the margin, concentrated near the body.
//   - Fast DUST DASHES carried by the wind.
//   White/gray, wispy, semi-transparent. Uses outfit_divine_aura_ext_vertex.
// donor client MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3  WIND_BRIGHT = vec3(0.96, 0.98, 1.00);
const vec3  WIND_GRAY   = vec3(0.55, 0.58, 0.63);

const float REACH_PX     = 18.0;
const float RIM_PX       = 3.0;
const float MARGIN_FADE  = 0.26;

const float WIDE_PX      = 22.0;
const float CIRC_LO      = 0.10;
const float CIRC_HI      = 0.40;

const float WIND_SPEED   = 1.3;   // how fast the streaks flow
const float STREAK_FREQ  = 30.0;  // number of streaks (perpendicular detail)
const float CURVE        = 0.06;   // how much the currents curve/swirl
const float WIND_GLOW    = 1.15;

vec2 hash2(vec2 p)
{
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(i).x;
    float b = hash2(i + vec2(1.0, 0.0)).x;
    float c = hash2(i + vec2(0.0, 1.0)).x;
    float d = hash2(i + vec2(1.0, 1.0)).x;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p)
{
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { s += a * vnoise(p); p *= 2.0; a *= 0.5; }
    return s;
}

// Curved wind speed-lines (noise stretched along the flow, scrolled).
float streaks(vec2 uv, float t)
{
    float curve = CURVE * sin(uv.x * 5.0 + t * 0.8);
    vec2 f1 = vec2(uv.x * 2.5 - t * WIND_SPEED,        (uv.y + curve) * STREAK_FREQ);
    vec2 f2 = vec2(uv.x * 3.6 - t * WIND_SPEED * 1.7 + 5.0, (uv.y + curve * 0.7) * (STREAK_FREQ * 1.5));
    float s1 = smoothstep(0.58, 0.84, fbm(f1));
    float s2 = smoothstep(0.60, 0.86, fbm(f2)) * 0.75;
    return max(s1, s2);
}

// Fast horizontal dust dashes.
float dust(vec2 uv, float t)
{
    vec2 gp = vec2(uv.x * 20.0 - t * 7.0, uv.y * 20.0);
    vec2 cell = floor(gp);
    vec2 f = fract(gp) - 0.5;
    vec2 r = hash2(cell + 31.0);
    if (r.x < 0.72) return 0.0;
    f.y += 0.3 * (r.y - 0.5);
    float d = length(vec2(f.x * 0.45, f.y * 2.2)); // elongated in x -> a dash
    return smoothstep(0.30, 0.0, d);
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;
    vec4 here = texture2D(u_Tex0, v_TexCoord);
    float aHere = here.a;

    float aSum = aHere, cnt = 1.0, rimSum = 0.0, rimCnt = 0.0, central = 0.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (REACH_PX * 0.5)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  REACH_PX).a;
        cnt += 2.0;
        rimSum += texture2D(u_Tex0, v_TexCoord + dir * px * RIM_PX).a;
        rimCnt += 1.0;
        central += texture2D(u_Tex0, v_TexCoord + dir * px * (WIDE_PX * 0.6)).a;
        central += texture2D(u_Tex0, v_TexCoord + dir * px *  WIDE_PX).a;
    }
    float reach  = aSum / cnt;
    float rimNbr = rimSum / rimCnt;
    central /= 16.0;

    float circ = 0.25 + 0.75 * smoothstep(CIRC_LO, CIRC_HI, central); // wind hugs the body
    float s = streaks(v_TexCoord, t) * circ;
    float d = dust(v_TexCoord, t) * circ;

    if (aHere > 0.5) {
        // Windswept body: desaturated, faint streaks, bright windward rim.
        float lum = dot(here.rgb, vec3(0.299, 0.587, 0.114));
        vec3 body = mix(here.rgb, vec3(lum), 0.45);   // blow the color out
        body = mix(body, WIND_GRAY, 0.12);
        body += WIND_BRIGHT * s * 0.35;
        body += WIND_BRIGHT * d * 0.5;

        float rim = clamp(1.0 - rimNbr, 0.0, 1.0);
        body += WIND_BRIGHT * rim * 0.35;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Currents + dust streaming off into the margin.
        if (reach < 0.03) discard;
        float life = smoothstep(0.0, MARGIN_FADE, reach);
        float sa = s * life;
        float da = d * life;
        float glow = reach * 0.05;
        float auraI = max(max(glow, sa * 0.8), da * 0.9) * WIND_GLOW;
        if (auraI < 0.02) discard;

        vec3 col = mix(WIND_GRAY * 0.6, WIND_BRIGHT, max(s, d));
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
