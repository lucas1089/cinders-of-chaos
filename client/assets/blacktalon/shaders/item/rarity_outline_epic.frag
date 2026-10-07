// Rarity - EPIC. A red FLAME aura licking the item, blending a few red
// tonalities (deep crimson tips -> strong red -> bright ember base).
// EXTENDED / PADDED shader (sprite drawn centered in a framebuffer with an ~8px
// margin so the flame can extend beyond the 32x32 cell). Body left untouched.
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

uniform float u_var0; // transmute dissolve: 1.0 = solid (normal), 0.0 = full dust

float dHash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float dNoise(vec2 p) {
    vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    float a = dHash(i), b = dHash(i + vec2(1.0, 0.0)), c = dHash(i + vec2(0.0, 1.0)), d = dHash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float dFbm(vec2 p) { float s = 0.0, a = 0.5; for (int k = 0; k < 4; k++) { s += a * dNoise(p); p *= 2.0; a *= 0.5; } return s; }

// Decode the packed u_var0 = transmute (0..1, 1 = solid) + chaosCount * 10.
float transmuteVal() { return u_var0 - floor(u_var0 / 10.0) * 10.0; }
float chaosCount()   { return floor(u_var0 / 10.0); }

// Transmute transition dissolve: transmuteVal 1 -> untouched; -> 0 crumbles to
// dust with a warm ember front. Keeps the item's look while disintegrating.
vec4 applyDissolve(vec4 cc) {
    float dsv = clamp(transmuteVal(), 0.0, 1.0);
    if (dsv >= 0.999) return cc;
    float n = dFbm(v_TexCoord * 9.0);
    float thresh = (1.0 - dsv) * 1.15 - 0.08;
    float keep = smoothstep(thresh - 0.06, thresh + 0.06, n);
    float ember = (1.0 - smoothstep(0.0, 0.14, abs(n - thresh))) * (1.0 - dsv);
    vec3 rgb = mix(cc.rgb, vec3(1.0, 0.55, 0.18), ember);
    return vec4(rgb, cc.a * keep);
}

// Corruption (ADDITIVE): N red dots (N = chaosCount) wandering over the item
// body, masked by the sprite alpha. Applied on the BODY only, not the outline.
vec4 applyCorruption(vec4 cc, vec3 rcol) {
    float n = chaosCount();
    if (n <= 0.0) return cc;
    float glow = 0.0;
    for (int i = 0; i < 3; i++) {
        if (float(i) >= n) break;
        float fi = float(i);
        vec2 p = vec2(0.5 + 0.28 * sin(u_Time * (0.6 + 0.13 * fi) + fi * 2.1),
                      0.5 + 0.28 * cos(u_Time * (0.5 + 0.11 * fi) + fi * 1.7));
        float d = distance(v_TexCoord, p);
        glow += smoothstep(0.045, 0.0, d);        // solid core
        glow += smoothstep(0.090, 0.0, d) * 0.35;  // soft halo
    }
    glow = clamp(glow, 0.0, 1.0);
    vec3 dotCol = mix(rcol, vec3(1.0), 0.25);      // brighten a touch for visibility
    vec3 rgb = mix(cc.rgb, dotCol, glow * 0.9);
    rgb += rcol * glow * 0.5;
    return vec4(rgb, cc.a);
}

const vec3 TIP_COL = vec3(0.70, 0.02, 0.04); // deep crimson (cool tips)
const vec3 MID_COL = vec3(1.00, 0.08, 0.03); // strong red
const vec3 HOT_COL = vec3(1.00, 0.24, 0.07); // hot red (kept red, not orange)

float rand(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Smooth value noise + fbm, used to make the flame flicker.
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = rand(i);
    float b = rand(i + vec2(1.0, 0.0));
    float c = rand(i + vec2(0.0, 1.0));
    float d = rand(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float sum = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        sum += amp * vnoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

// Max sprite alpha on a ring `dist` texels away (8 directions).
float ringAlpha(float dist) {
    float d = dist / 64.0;
    float dd = d * 0.707;
    return max(max(max(
        max(texture2D(u_Tex0, v_TexCoord + vec2( d, 0.0)).a,
            texture2D(u_Tex0, v_TexCoord + vec2(-d, 0.0)).a),
        max(texture2D(u_Tex0, v_TexCoord + vec2(0.0,  d)).a,
            texture2D(u_Tex0, v_TexCoord + vec2(0.0, -d)).a)),
        max(texture2D(u_Tex0, v_TexCoord + vec2( dd,  dd)).a,
            texture2D(u_Tex0, v_TexCoord + vec2(-dd,  dd)).a)),
        max(texture2D(u_Tex0, v_TexCoord + vec2( dd, -dd)).a,
            texture2D(u_Tex0, v_TexCoord + vec2(-dd, -dd)).a));
}

void main() {
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    if (col.a > 0.01) {
        gl_FragColor = applyDissolve(applyCorruption(col, MID_COL)); // body + corruption dots
    } else {
        // Radial "heat": 1.0 hugging the item edge, fading into the margin.
        float heat =
            max(ringAlpha(1.5)  * 1.00,
            max(ringAlpha(3.0)  * 0.80,
            max(ringAlpha(5.0)  * 0.58,
            max(ringAlpha(7.0)  * 0.36,
                ringAlpha(9.0)  * 0.18))));
        if (heat < 0.01) discard;

        // Turbulence whose domain scrolls down -> tongues appear to rise.
        vec2 fp = v_TexCoord * vec2(7.0, 9.0);
        fp.y += u_Time * 0.55;
        float turb = 0.55 * fbm(fp) + 0.45 * fbm(fp * 2.3 + 5.0);
        float flame = smoothstep(0.08, 0.78, heat * (0.55 + 0.95 * turb));
        flame *= 0.92 + 0.08 * sin(u_Time * 4.5 + turb * 6.0); // gentle flicker
        if (flame < 0.01) discard;

        // Blend the red tonalities by heat: crimson tips -> red -> ember base.
        vec3 flameCol = mix(TIP_COL, MID_COL, smoothstep(0.0, 0.35, heat));
        flameCol = mix(flameCol, HOT_COL, smoothstep(0.78, 1.0, heat * (0.6 + 0.4 * flame)));

        gl_FragColor = applyDissolve(vec4(flameCol * flame, flame));
    }
}
