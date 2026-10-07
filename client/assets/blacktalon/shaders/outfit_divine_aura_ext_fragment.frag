// Divine Aura (EXTENDED) fragment - a holy, all-blue effect whose aura EXTENDS
// beyond the character, into the 25px padded margin of the extended-shader
// framebuffer.
//  - Body: kept lit, tinted lightly blue, with divine light bands streaming down.
//  - Aura: a blue glow that fades outward from the silhouette into the margin.
//    Its alpha follows its brightness, so faint areas are transparent (no black).
//
// Runs on the composited framebuffer (already colored), so it does NOT apply the
// u_Color mask. Edge distance is estimated by blurring the framebuffer alpha
// (dFdx/dFdy give the texel size). Uses outfit_divine_aura_ext_vertex.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Holy blue palette.
const vec3  DIVINE_BLUE  = vec3(0.30, 0.60, 1.00);
const vec3  DIVINE_LIGHT = vec3(0.78, 0.92, 1.00);

const float TINT_AMOUNT   = 0.30; // how blue the body gets (0 = untouched)

// Downward "divine light" streaming over the body (texcoord units).
const float BAND_FREQ     = 9.0;
const float DESCEND_SPEED = 1.5;  // flip the sign in `phase` if it goes the wrong way
const float BAND_STRENGTH = 0.45;

// Aura reach (screen pixels) and brightness. Can reach up to the 25px margin.
const float GLOW_PIXELS   = 11.0;
const float AURA_POWER    = 1.7;

void main()
{
    vec4 here = texture2D(u_Tex0, v_TexCoord);
    float aHere = here.a;

    // Texel size from derivatives (adapts to the framebuffer scale).
    vec2 px = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
    if (px.x < 1e-6) px.x = 0.003;
    if (px.y < 1e-6) px.y = 0.003;

    // Blur the alpha over a small kernel -> high near/inside the body, fading to
    // 0 out in the margin. Doubles as a cheap distance-to-silhouette field.
    float aSum = aHere;
    float cnt  = 1.0;
    for (int i = 0; i < 8; i++) {
        float ang = float(i) * 0.7853981; // 45 deg steps
        vec2 dir = vec2(cos(ang), sin(ang));
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (GLOW_PIXELS * 0.35)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px * (GLOW_PIXELS * 0.70)).a;
        aSum += texture2D(u_Tex0, v_TexCoord + dir * px *  GLOW_PIXELS).a;
        cnt  += 3.0;
    }
    float blurA = aSum / cnt;

    // Downward streaming phase (flip + to - if it flows upward on your build).
    float t = u_Time;
    float phase = v_TexCoord.y * BAND_FREQ + t * DESCEND_SPEED;

    if (aHere > 0.5) {
        // Body: keep lit, tint lightly blue, add descending divine light + rim.
        float lum = dot(here.rgb, vec3(0.299, 0.587, 0.114));
        vec3 body = mix(here.rgb, DIVINE_BLUE * (0.5 + lum), TINT_AMOUNT);

        float band = pow(0.5 + 0.5 * sin(phase), 4.0);
        body += DIVINE_LIGHT * band * BAND_STRENGTH;

        float innerRim = clamp(1.0 - blurA, 0.0, 1.0);
        body += DIVINE_BLUE * innerRim * 0.5;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Outer aura: blue, fading outward (brightness = blurA). Alpha follows
        // brightness so there is never a dark halo.
        float shimmer = 0.6 + 0.4 * sin(phase);
        float auraI = blurA * shimmer * AURA_POWER;
        if (auraI < 0.02) discard;

        vec3 col = mix(DIVINE_LIGHT, DIVINE_BLUE, blurA); // whiter far out, deeper blue near body...
        gl_FragColor = vec4(col, clamp(auraI, 0.0, 1.0));
    }
}
