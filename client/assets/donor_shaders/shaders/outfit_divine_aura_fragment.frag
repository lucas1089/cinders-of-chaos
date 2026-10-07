// Divine Aura (outfit) fragment - a holy, all-blue effect.
//  - The body is kept fully lit and just tinted lightly blue (not darkened).
//  - Soft blue "divine light" bands stream DOWNWARD across the body.
//  - A blue rim aura hugs the silhouette; its alpha tracks its brightness, so
//    dim areas are transparent (no black halo around the character).
//
// The silhouette edge is found by blurring the sprite alpha (dFdx/dFdy give the
// texel size). v_LocalPos (a_Vertex - u_Center) drives the descending motion, so
// it is body-attached and continuous across tiles. Uses outfit_darkboost_vertex.
// donor client MMORPG

uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_LocalPos;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Holy blue palette.
const vec3  DIVINE_BLUE  = vec3(0.30, 0.60, 1.00); // main aura blue
const vec3  DIVINE_LIGHT = vec3(0.78, 0.92, 1.00); // bright blue-white highlight

// Body tint (how blue the character gets; 0 = untouched, 1 = fully blue).
const float TINT_AMOUNT  = 0.30;

// Downward "divine light" streaming over the body.
const float BAND_FREQ    = 0.26; // band density
const float DESCEND_SPEED= 2.0;  // downward flow speed (flip sign to go up)
const float BAND_STRENGTH= 0.45; // brightness of the streaming light

// Rim aura around the silhouette.
const float GLOW_PIXELS  = 5.0;  // aura thickness (screen pixels)
const float AURA_POWER   = 1.6;  // aura brightness

void main()
{
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor  = texture2D(u_Tex0, v_TexCoord2);
    float aHere = baseColor.a;

    // Standard outfit color application (head/body/legs/feet via the mask).
    if (aHere > 0.01) {
        if (texcolor.r > 0.9) {
            baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
        } else if (texcolor.g > 0.9) {
            baseColor *= u_Color[2];
        } else if (texcolor.b > 0.9) {
            baseColor *= u_Color[3];
        }
    }

    // --- Silhouette edge band from a small alpha blur ---
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    float aSum = aHere;
    float cnt  = 1.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981; // 45 deg steps
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (GLOW_PIXELS * 0.5)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  GLOW_PIXELS).a;
        cnt  += 2.0;
    }
    float blurA = aSum / cnt;
    float edgeBand = 1.0 - abs(2.0 * blurA - 1.0); // peaks on the outline

    // Downward-streaming phase (screen y grows down, so -t descends).
    float t = u_Time;
    float phase = v_LocalPos.y * BAND_FREQ - t * DESCEND_SPEED;

    if (aHere > 0.5) {
        // Body: keep it lit, tint lightly blue, add descending divine light.
        float lum = dot(baseColor.rgb, vec3(0.299, 0.587, 0.114));
        vec3 body = mix(baseColor.rgb, DIVINE_BLUE * (0.5 + lum), TINT_AMOUNT);

        float band = pow(0.5 + 0.5 * sin(phase), 4.0); // sharp bright bands falling
        body += DIVINE_LIGHT * band * BAND_STRENGTH;

        // Faint inner rim so the silhouette glows softly too.
        body += DIVINE_BLUE * edgeBand * 0.35;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), baseColor.a);
    } else {
        // Outer aura: ALWAYS a blue color; alpha follows brightness so faint
        // areas are transparent (never a black halo).
        float shimmer = 0.55 + 0.45 * sin(phase);
        float auraI = edgeBand * shimmer * AURA_POWER;
        if (auraI < 0.02) discard;

        vec3 col = mix(DIVINE_BLUE, DIVINE_LIGHT, edgeBand); // brighter at the edge
        gl_FragColor = vec4(col, clamp(auraI, 0.0, 1.0));
    }
}
