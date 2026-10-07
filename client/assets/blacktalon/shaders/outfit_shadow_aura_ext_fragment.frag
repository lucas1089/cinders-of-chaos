// Shadow Aura (EXTENDED) fragment - the exact same effect as the Divine Aura,
// but in a BLACK/GRAY palette. Body darkened & desaturated toward gray, SILVER
// light bands streaming down (so they read against the dark body), and a smoky
// dark aura that EXTENDS beyond the character into the 25px padded margin.
//
// Same mechanics as the divine version: runs on the composited framebuffer
// (already colored, so no u_Color mask), edge distance from an alpha blur
// (dFdx/dFdy). Uses outfit_divine_aura_ext_vertex.
// BlackTalon MMORPG

varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;

// Black / gray palette.
const vec3  BODY_GRAY    = vec3(0.22, 0.22, 0.26); // gray the body tints to
const vec3  BAND_DARK    = vec3(0.03, 0.03, 0.05); // DARK streak color (shadow wave)
const vec3  AURA_DARK    = vec3(0.02, 0.02, 0.03); // near-black smoke (near body)
const vec3  AURA_GRAY    = vec3(0.16, 0.16, 0.20); // gray smoke (outer)

const float TINT_AMOUNT   = 0.42; // how strongly the body goes gray

// Downward DARK wave sweeping over the body (a shadow streak, not a light one).
// It darkens the body where the band passes, so it reads on the dark body.
const float BAND_FREQ     = 9.0;
const float DESCEND_SPEED = 1.5;  // flip the sign in `phase` if it goes the wrong way
const float BAND_STRENGTH = 0.70; // how dark the sweeping streak gets

// Aura reach (screen pixels) and opacity. Can reach up to the 25px margin.
const float GLOW_PIXELS   = 11.0;
const float AURA_POWER    = 1.35;

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
        // Body: darken & desaturate toward gray, add descending silver light + rim.
        float lum = dot(here.rgb, vec3(0.299, 0.587, 0.114));
        vec3 body = mix(here.rgb, BODY_GRAY * (0.5 + lum), TINT_AMOUNT);

        float band = pow(0.5 + 0.5 * sin(phase), 4.0);
        // Dark wave passing: darken the body toward BAND_DARK where the band is.
        // (For a LIGHT streak instead, use: body += vec3(0.85) * band * BAND_STRENGTH;)
        body = mix(body, BAND_DARK, band * BAND_STRENGTH);

        float innerRim = clamp(1.0 - blurA, 0.0, 1.0);
        body += AURA_GRAY * innerRim * 0.6;

        gl_FragColor = vec4(clamp(body, 0.0, 1.0), here.a);
    } else {
        // Outer aura: smoky dark, fading outward. Alpha follows the field so it
        // reads as translucent shadow (not a solid black blob).
        float shimmer = 0.6 + 0.4 * sin(phase);
        float auraI = blurA * shimmer * AURA_POWER;
        if (auraI < 0.02) discard;

        vec3 col = mix(AURA_GRAY, AURA_DARK, blurA); // darker near the body
        gl_FragColor = vec4(col, clamp(auraI, 0.0, 1.0));
    }
}
