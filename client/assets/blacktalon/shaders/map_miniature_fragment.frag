
// MINIATURE (tilt-shift) — pure LOOK, NO geometry.
//
// Makes the world read as a tiny hand-built model: a sharp band of focus through
// the player's row, softly defocused above and below, with richer colour and a
// gentle vignette. It changes NO positions, so unlike the perspective tilt it
// cannot skew buildings, split tiling art, morph while walking, or desync mouse
// picking / name plates / lighting. Pure data — no C++, no rebuild.
//
// The focal band is anchored to the SCREEN via gl_FragCoord (safe here precisely
// because nothing is warped): sharp through the map panel's middle row (~ the
// player), regardless of map scroll.
//
// TUNING — edit and relaunch:
//   FOCUS    where the sharp band sits (0 = panel center / player row).
//   BAND     half-height of the sharp band (bigger = more of the map crisp).
//   BLUR     defocus radius in uv. Keep small — Tibia is fine pixel art.
//   SAT      colour richness. Miniatures look hyper-saturated.
//   VIGNETTE corner darkening. 0 disables.

varying vec2 v_TexCoord;
uniform vec4 u_Color;
uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;   // render target size (px)
uniform vec2 u_Center;       // map panel center, painter px, y-down

const float FOCUS    = 0.0;
const float BAND     = 0.34;
const float BLUR     = 0.0032;
const float SAT      = 1.18;
const float VIGNETTE = 0.16;

vec4 tap(vec2 uv, vec2 o)
{
    return texture2D(u_Tex0, clamp(uv + o, vec2(0.001), vec2(0.999)));
}

void main()
{
    // Screen-space vertical position, 0 at the panel center. gl_FragCoord is GL
    // y-up; flip to painter y-down to match u_Center. Normalized by the viewport
    // half-height (approximate — this only shapes a soft blur band, not geometry).
    float painterY = u_Resolution.y - gl_FragCoord.y;
    float halfH = max(u_Resolution.y * 0.5, 1.0);
    float ny = (painterY - u_Center.y) / halfH;

    // Defocus rises smoothly outside the band, squared so the sharp region holds
    // and the falloff feels optical rather than linear.
    float d = abs(ny - FOCUS);
    float k = clamp((d - BAND) / max(1.0 - BAND, 1e-4), 0.0, 1.0);
    float r = k * k * BLUR;

    vec4 col = texture2D(u_Tex0, v_TexCoord);

    if (r > 0.00002) {
        // 12 taps on two rings — cheap, round enough that highlights defocus
        // into discs instead of a cross.
        float ri = r * 0.55;
        vec4 s = col * 2.0;                     // centre weighted
        s += tap(v_TexCoord, vec2( ri,   0.0));
        s += tap(v_TexCoord, vec2(-ri,   0.0));
        s += tap(v_TexCoord, vec2( 0.0,  ri));
        s += tap(v_TexCoord, vec2( 0.0, -ri));
        s += tap(v_TexCoord, vec2( ri*0.7,  ri*0.7));
        s += tap(v_TexCoord, vec2(-ri*0.7,  ri*0.7));
        s += tap(v_TexCoord, vec2( ri*0.7, -ri*0.7));
        s += tap(v_TexCoord, vec2(-ri*0.7, -ri*0.7));
        s += tap(v_TexCoord, vec2( r,    0.0));
        s += tap(v_TexCoord, vec2(-r,    0.0));
        s += tap(v_TexCoord, vec2( 0.0,  r));
        s += tap(v_TexCoord, vec2( 0.0, -r));
        col = s / 14.0;
    }

    // Richer colour, the signature of the miniature look.
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    col.rgb = mix(vec3(lum), col.rgb, SAT);

    // Gentle screen-anchored vignette.
    float vx = gl_FragCoord.x / u_Resolution.x - 0.5;
    vec2 vp = vec2(vx, ny * 0.5);
    float v = 1.0 - VIGNETTE * clamp(dot(vp, vp) * 3.0, 0.0, 1.0);
    col.rgb *= v;

    col *= u_Color;
    gl_FragColor = vec4(clamp(col.rgb, 0.0, 1.0), col.a);
}
