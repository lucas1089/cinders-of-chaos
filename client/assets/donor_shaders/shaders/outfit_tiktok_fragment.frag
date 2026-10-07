// TikTok (outfit) fragment - darkened body + an animated NEON EDGE GLOW that
// hugs the silhouette, with bright bands travelling diagonally along the outline
// (the "onda diagonal" look) and the color flowing between TikTok CYAN and PINK.
//
// The silhouette edge is found by blurring the sprite alpha (dFdx/dFdy give the
// texel size, same trick as outline_testOutline). edgeBand peaks right on the
// outline (inside + outside), so the glow straddles the border like a rim light.
// v_LocalPos (a_Vertex - u_Center) drives the wave, so it is body-attached and
// continuous. Uses outfit_darkboost_vertex.
// donor client MMORPG

uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_LocalPos;
uniform sampler2D u_Tex0;
uniform float u_Time;

// TikTok brand colors.
const vec3  TT_CYAN     = vec3(0.145, 0.957, 0.933); // #25F4EE
const vec3  TT_PINK     = vec3(0.996, 0.173, 0.333); // #FE2C55

const float DARKNESS    = 0.55;  // how much to darken the body (neon pops on dark)
const float GLOW_PIXELS = 5.0;   // outline glow thickness (screen pixels)
const float GLOW_POWER  = 1.7;   // overall neon brightness

// Travelling diagonal wave (bright bands running along the outline).
const float WAVE_FREQ   = 0.16;  // band density
const float WAVE_SPEED  = 2.4;   // band travel speed

// Slow cyan<->pink color flow along the body.
const float FLOW_FREQ   = 0.05;
const float FLOW_SPEED   = 1.1;

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
    float edgeBand = 1.0 - abs(2.0 * blurA - 1.0); // peaks right on the outline

    // --- Travelling wave + cyan/pink flow (body-attached coords) ---
    float t = u_Time;
    float diag = v_LocalPos.x + v_LocalPos.y;
    float wave = 0.55 + 0.45 * sin(diag * WAVE_FREQ - t * WAVE_SPEED);
    float cmix = 0.5  + 0.5  * sin(diag * FLOW_FREQ - t * FLOW_SPEED);
    vec3  glowColor = mix(TT_CYAN, TT_PINK, cmix);

    float glow = edgeBand * wave;

    if (aHere > 0.5) {
        // Darkened body with a faint cool sheen, plus the inner edge glow.
        vec3 body = baseColor.rgb * (1.0 - DARKNESS) + TT_CYAN * 0.04;
        vec3 col = body + glowColor * glow * GLOW_POWER;
        gl_FragColor = vec4(clamp(col, 0.0, 1.0), baseColor.a);
    } else {
        // Outside the silhouette: draw only the outer glow, transparent elsewhere.
        float outA = clamp(glow * GLOW_POWER, 0.0, 1.0);
        if (outA < 0.01) discard;
        vec3 col = clamp(glowColor * glow * GLOW_POWER, 0.0, 1.0);
        gl_FragColor = vec4(col, outA);
    }
}
