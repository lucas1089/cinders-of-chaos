// Rarity: Metal - PURPLE (Mythic). EXTENDED / PADDED item shader.
// Same family as rarity_metal_cyan (Divine) but tinted purple and using the
// PARALLEL-WAVES glow: bands parallel to the silhouette that ripple outward.
// Registered as an extended shader so the sprite is drawn centered in a padded
// framebuffer and the outline glow can extend beyond the 32x32 cell.
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

const vec3  METAL_TINT     = vec3(0.70, 0.22, 1.00); // purple (Mythic ~#a30ff6)
const float METAL_STRENGTH = 0.25;                   // 0..1: lower = more original color shows

float rand(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float starGlint(vec2 uv, vec2 p, float size, float phase) {
    // Spike grows/shrinks over time (per-glint phase, out of sync); brightness
    // follows the size so they read as breathing spikes.
    float pulse = 0.5 + 0.5 * sin(u_Time * 2.2 + phase * 1.6);
    float sz = size * (0.28 + 0.85 * pulse);
    float tw = pow(0.35 + 0.75 * pulse, 1.4);
    vec2 d = (uv - p) / sz;
    float core = smoothstep(1.0, 0.0, length(d));
    float rx = smoothstep(1.0, 0.0, abs(d.y)) * smoothstep(6.0, 0.0, abs(d.x));
    float ry = smoothstep(1.0, 0.0, abs(d.x)) * smoothstep(6.0, 0.0, abs(d.y));
    return (core + (rx + ry) * 0.8) * tw;
}

float glintField(vec2 uv, float size, float seed) {
    float g = 0.0;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        vec2 p = vec2(rand(vec2(fi, seed)), rand(vec2(fi, seed + 3.0)));
        g += starGlint(uv, p, size, fi * 2.3 + seed);
    }
    return g;
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

// Approx distance (in texels, ~1..8) to the nearest opaque sprite pixel; 9 = far.
float edgeDist() {
    for (int i = 1; i <= 8; i++) {
        if (ringAlpha(float(i)) > 0.35) {
            return float(i);
        }
    }
    return 9.0;
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    float alpha = col.a;

    vec2 texel = vec2(1.0 / 64.0);
    float nAlpha = (
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texel.y)).a) * 0.25;

    vec3 tint = METAL_TINT;
    float s = METAL_STRENGTH;

    if (alpha > 0.01) {
        // --- Desaturated tinted body ---
        float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
        vec3 metal = tint * (0.30 + 0.85 * lum);
        vec3 base = mix(col.rgb, metal, s);

        float rim = clamp((alpha - nAlpha) * 3.5, 0.0, 1.0);
        base += vec3(0.55) * rim * s;

        float diag = clamp((v_TexCoord.x - v_TexCoord.y) * 0.5 + 0.5, 0.0, 1.0);
        float sweep = fract(u_Time * 0.22);
        float band = smoothstep(0.10, 0.0, abs(fract(diag - sweep + 0.5) - 0.5));
        base += vec3(0.90) * band * (0.4 + 0.6 * lum) * s;

        base += vec3(1.0) * glintField(v_TexCoord, 0.06, 3.7) * 1.5 * s;

        gl_FragColor = applyDissolve(applyCorruption(vec4(base, alpha), METAL_TINT));
    } else {
        // --- OUTLINE GLOW with PARALLEL WAVES flowing outward ---
        float dEdge   = edgeDist();                             // ~1..8 texels
        float falloff = pow(smoothstep(7.5, 0.0, dEdge), 1.1);  // thin, fades out
        float wave = 0.55 + 0.45 * sin(dEdge * 1.15 - u_Time * 4.0);

        float glint = glintField(v_TexCoord, 0.035, 8.1);

        vec3 glowColor = mix(tint, vec3(1.0), 0.35);
        float glowI = clamp(falloff * 1.5, 0.0, 1.0) * wave;

        // Light diagonal SWEEP passing across the glow (subtle).
        float coord = (v_TexCoord.x + v_TexCoord.y) * 0.5;
        float band  = smoothstep(0.16, 0.0, abs(coord - (fract(u_Time * 0.20) * 1.4 - 0.2)));
        glowI *= 1.0 + 0.45 * band;
        glowColor = mix(glowColor, vec3(1.0), band * 0.30);

        vec3 c = glowColor * glowI + vec3(1.0) * glint * s;
        float a = clamp(glowI + glint * s, 0.0, 1.0);
        if (a < 0.01) {
            discard;
        }
        gl_FragColor = applyDissolve(vec4(c, a));
    }
}
