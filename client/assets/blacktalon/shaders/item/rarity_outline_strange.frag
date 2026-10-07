// Rarity outline - STRANGE (grey). Simple, thin, static outline around the item.
// EXTENDED/PADDED shader so the outline can extend a bit beyond the 32x32 cell.
// The item body is left with its original colors; only a tinted rim is added.
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

const vec3 TINT = vec3(0.77, 0.81, 0.74); // grey (#c4cebc)

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
        gl_FragColor = applyDissolve(applyCorruption(col, TINT)); // body + corruption dots
    } else {
        float outline = max(ringAlpha(1.5) * 1.00,
                        max(ringAlpha(3.0) * 0.45,
                            ringAlpha(4.0) * 0.15));
        float glowI = clamp(outline * 1.15, 0.0, 1.0);
        if (glowI < 0.01) discard;
        gl_FragColor = applyDissolve(vec4(mix(TINT, vec3(1.0), 0.20) * glowI, glowI));
    }
}
