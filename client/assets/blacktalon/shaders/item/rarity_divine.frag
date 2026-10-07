// Rarity: Metal (MU Online style "divine metal") - shared shader for the silver
// (rare) and cyan (epic) rarities. The METAL TINT comes from u_Color (the item
// widget's setColor), so one shader serves any color. Desaturated tinted base +
// glassy rim + moving reflection sweep + twinkling STAR-shaped sparkle glints.
// Vertex shader: item_transmute_blackout_vertex (standard item vertex).
uniform float u_Time;
uniform sampler2D u_Tex0;
uniform vec4 u_Color;   // metal tint fed by the widget's setColor
varying vec2 v_TexCoord;

float rand(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// A twinkling 4-point star glint centered at p (uv space): bright core + thin
// horizontal/vertical rays, pulsing sharply on and off.
float starGlint(vec2 uv, vec2 p, float size, float phase) {
    // Softer twinkle (pow 1.6) so glints stay visible longer / more often.
    float tw = pow(0.5 + 0.5 * sin(u_Time * 2.8 + phase), 1.6);
    vec2 d = (uv - p) / size;
    float core = smoothstep(1.0, 0.0, length(d));
    float rx = smoothstep(1.0, 0.0, abs(d.y)) * smoothstep(6.0, 0.0, abs(d.x));
    float ry = smoothstep(1.0, 0.0, abs(d.x)) * smoothstep(6.0, 0.0, abs(d.y));
    return (core + (rx + ry) * 0.8) * tw;
}

// Sum of several seeded star glints (fixed loop count for ANGLE).
float glintField(vec2 uv, float size, float seed) {
    float g = 0.0;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        vec2 p = vec2(rand(vec2(fi, seed)), rand(vec2(fi, seed + 3.0)));
        g += starGlint(uv, p, size, fi * 2.3 + seed);
    }
    return g;
}

// Max sprite alpha found on a ring `dist` texels away (8 directions) - used to
// build the outline glow that hugs the item's silhouette.
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

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    float alpha = col.a;

    // Neighbor alpha for edge/rim detection (~1px on a 64px sprite).
    vec2 texel = vec2(1.0 / 64.0);
    float nAlpha = (
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texel.y)).a) * 0.25;

    // Metal tint (silver, cyan, ...) from the widget color, and the effect
    // strength from its alpha: 1.0 = full metal, lower blends the original item
    // colors back in and fades the highlights.
    vec3 tint = u_Color.rgb;
    float s = clamp(u_Color.a, 0.0, 1.0);

    if (alpha > 0.01) {
        // --- Desaturated tinted base, mixed back toward the original by (1-s) ---
        float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
        vec3 metal = tint * (0.30 + 0.85 * lum);
        vec3 base = mix(col.rgb, metal, s);

        // --- Glassy bright rim on the inner edge ---
        float rim = clamp((alpha - nAlpha) * 3.5, 0.0, 1.0);
        base += vec3(0.55) * rim * s;

        // --- Moving reflection sweep (diagonal specular band) ---
        float diag = clamp((v_TexCoord.x - v_TexCoord.y) * 0.5 + 0.5, 0.0, 1.0);
        float sweep = fract(u_Time * 0.22);
        float bandDist = abs(fract(diag - sweep + 0.5) - 0.5);
        float band = smoothstep(0.10, 0.0, bandDist);
        base += vec3(0.90) * band * (0.4 + 0.6 * lum) * s;

        // --- Bright star glints twinkling ON TOP of the item (more & bolder) ---
        float glint = glintField(v_TexCoord, 0.06, 3.7);
        base += vec3(1.0) * glint * 1.5 * s;

        gl_FragColor = vec4(base, alpha);
    } else {
        // --- Tinted OUTLINE GLOW hugging the silhouette + sparkles around ---
        // Layered rings: closer to the item = brighter, fading outward. Outer
        // rings kept strong so the glow reads as a thicker, clearer halo.
        float outline =
            max(ringAlpha(1.0) * 1.00,
            max(ringAlpha(2.0) * 0.90,
            max(ringAlpha(3.0) * 0.72,
                ringAlpha(4.0) * 0.48)));
        // Outline glow stays on at full strength (no pulse), unlike the sparkles.

        float glint = glintField(v_TexCoord, 0.035, 8.1);

        // Brighter, lighter glow: push the tint toward white and boost intensity
        // so the halo is clearly visible on the dark background. Sparkles stay
        // white and scale with the effect strength.
        vec3 glowColor = mix(tint, vec3(1.0), 0.35);
        float glowI = clamp(outline * 1.4, 0.0, 1.0);
        vec3 col = glowColor * glowI + vec3(1.0) * glint * s;
        float a = clamp(glowI + glint * s, 0.0, 1.0);
        if (a < 0.01) {
            discard;
        }
        gl_FragColor = vec4(col, a);
    }
}
