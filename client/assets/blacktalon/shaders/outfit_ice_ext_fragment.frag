// Articuno Ice (EXTENDED) fragment - the character is frozen in glassy ice with
// sharp ICE CRYSTAL SHARDS radiating outward. Built from scratch:
//   - Body: frozen glass - desaturated + cold blue tint, frosted-glass mottling,
//     a bright frost RIM on the silhouette, and twinkling ICE GLINTS.
//   - Margin: radial CRYSTAL SHARDS anchored to the silhouette. Each shard is a
//     tapering triangle (wide at the body, sharp point outward) whose length
//     follows the alpha "reach" field, with a white core edge and a slow inner
//     shimmer (light catching the crystal). Plus a faint cold MIST.
//   Different technique from the lightning (solid tapering crystals vs flickering
//   thin bolts). Uses outfit_divine_aura_ext_vertex.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

const vec3  ICE_DEEP  = vec3(0.16, 0.46, 0.78); // cold blue
const vec3  ICE_LIGHT = vec3(0.74, 0.92, 1.00); // pale ice
const vec3  WHITE      = vec3(0.95, 1.00, 1.00);

const float ANG_SLOTS   = 24.0;  // angular density of emitted ice shards
const float BANDS       = 6.0;   // shard rings across the margin depth
const float EMIT_SPEED  = 1.7;   // outward drift speed (higher = more frequent)
const float SHARD_OPAC  = 0.90;  // shard opacity
const float REACH_PX    = 20.0;  // how far shards / mist reach into the margin
const float RIM_PX      = 3.0;   // frost rim thickness
const float GLINT_SCALE = 12.0;  // ice-glint density
const float FROST_GLOW  = 1.3;   // crystal brightness

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

// Sharp, twinkling ice glint (a bright point with a 4-point sparkle).
float glint(vec2 uv, float t)
{
    vec2 g = uv * GLINT_SCALE;
    vec2 c = floor(g), f = fract(g);
    vec2 r = hash2(c);
    vec2 pos = vec2(0.5) + 0.28 * vec2(sin(t + r.x * 6.2831), cos(t * 1.1 + r.y * 6.2831));
    vec2 d = f - pos;
    float tw = pow(0.5 + 0.5 * sin(t * 2.5 + r.x * 6.2831), 6.0);
    float core = smoothstep(0.06, 0.0, length(d));
    float ray = smoothstep(0.02, 0.0, abs(d.x)) * smoothstep(0.22, 0.0, abs(d.y))
              + smoothstep(0.02, 0.0, abs(d.y)) * smoothstep(0.22, 0.0, abs(d.x));
    return (core + ray * 0.6) * tw;
}

void main()
{
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float t = u_Time;
    vec4 here = texture2D(u_Tex0, v_TexCoord);
    float aHere = here.a;

    // Wide "reach" field (shards + mist) and a tight rim field.
    float aSum = aHere, cnt = 1.0, rimSum = 0.0, rimCnt = 0.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981;
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (REACH_PX * 0.5)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  REACH_PX).a;
        cnt += 2.0;
        rimSum += texture2D(u_Tex0, v_TexCoord + dir * px * RIM_PX).a;
        rimCnt += 1.0;
    }
    float reach   = aSum / cnt;
    float rimNbr  = rimSum / rimCnt;

    // Character is centered in the framebuffer; crystals radiate from here.
    vec2 p = v_TexCoord - 0.5;

    if (aHere > 0.5) {
        // Frozen glass body: desaturate toward cold, cool tint, frost mottle.
        float lum = dot(here.rgb, vec3(0.299, 0.587, 0.114));
        vec3 body = mix(here.rgb, mix(vec3(lum), ICE_LIGHT, 0.5), 0.75);
        body = mix(body, ICE_DEEP, 0.15);
        body += ICE_LIGHT * (fbm(v_TexCoord * 22.0 + t * 0.05) - 0.5) * 0.14;

        // Bright frost rim on the silhouette + twinkling ice glints.
        float rim = clamp(1.0 - rimNbr, 0.0, 1.0);
        body += ICE_LIGHT * rim * 0.7;
        body += WHITE * glint(v_TexCoord, t) * 0.9;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Hard guard: only draw near the silhouette (kills stray far artifacts).
        if (reach < 0.03) discard;

        // ICE SHARDS emitted from the body OUTWARD, then EVAPORATING. The margin
        // depth is measured by `reach` (1 at the body -> 0 at the outer margin).
        // Shard bands scroll toward lower reach over time (outward drift), broken
        // into discrete pieces by angular slots, and fade out as they reach the
        // margin edge -> ice pouring off the body and dissolving.
        float ang = atan(p.y, p.x) * 0.159155 + 0.5;

        float band = reach * BANDS + t * EMIT_SPEED; // + => feature drifts outward
        float bandId = floor(band);
        float bf = fract(band);
        float radialBlob = smoothstep(0.5, 0.06, abs(bf - 0.5)); // thin shard along reach

        float slot = floor(ang * ANG_SLOTS);
        vec2 sh = hash2(vec2(slot, bandId));
        float present = step(0.45, sh.x);                        // ~55% slots emit
        float ac = fract(ang * ANG_SLOTS + (sh.y - 0.5) * 0.7);  // jittered angular pos
        float angBlob = smoothstep(0.45, 0.05, abs(ac - 0.5));

        float shard = radialBlob * angBlob * present;

        // Evaporate: strong near the body, fading to nothing at the outer margin.
        float life = smoothstep(0.0, 0.22, reach);
        float glow = shard * life;

        float mist = reach * 0.10;
        float auraI = max(glow * SHARD_OPAC, mist) * FROST_GLOW;
        if (auraI < 0.02) discard;

        vec3 col = mix(ICE_DEEP, ICE_LIGHT, shard);
        col = mix(col, WHITE, radialBlob * angBlob * 0.6);       // white crystal core
        col += WHITE * glint(v_TexCoord, t) * shard;
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(auraI, 0.0, 1.0));
    }
}
