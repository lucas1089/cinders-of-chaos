// Divine soul-scroll corruption: a soft, PULSING cyan-silver glow.
//  * body   -> a gentle cyan sheen scaled by luminance, so the sprite keeps its
//              shape/detail instead of being washed flat cyan;
//  * rim    -> a brighter inner edge highlight;
//  * outer  -> a SOFT, TRANSLUCENT halo built from a radial ring falloff (real
//              alpha opacity, not a hard opaque ring).
// All modulated by one breathing pulse. Vertex: item_transmute_blackout_vertex.
uniform sampler2D u_Tex0;
uniform float u_Time;

varying vec2 v_TexCoord;

const float PS = 1.0 / 64.0;   // one texel on a 64px item sprite

// Max sprite alpha on a ring `dist` texels away (8 directions).
float ringAlpha(float dist) {
    float d = dist * PS;
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

    // Breathing pulse 0..1.
    float pulse = 0.5 + 0.5 * sin(u_Time * 2.5);

    vec3 divine = vec3(0.45, 0.85, 1.0);   // cyan
    vec3 hi     = vec3(0.85, 0.98, 1.0);   // near-white rim highlight

    if (col.a > 0.01) {
        // Inner-rim mask.
        float nAvg = (
            texture2D(u_Tex0, v_TexCoord + vec2( PS, 0.0)).a +
            texture2D(u_Tex0, v_TexCoord + vec2(-PS, 0.0)).a +
            texture2D(u_Tex0, v_TexCoord + vec2(0.0,  PS)).a +
            texture2D(u_Tex0, v_TexCoord + vec2(0.0, -PS)).a) * 0.25;
        float rim = clamp((1.0 - nAvg) * 2.2, 0.0, 1.0);

        float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));

        // Gentle cyan sheen scaled by luminance -> keeps the sprite readable.
        vec3 c = col.rgb + divine * lum * (0.12 + 0.32 * pulse);
        // Rim highlight, pulsing.
        c += hi * rim * (0.35 + 0.45 * pulse);

        gl_FragColor = vec4(c, col.a);
    } else {
        // Soft outer halo: radial falloff (closer rings weigh more), smoothed, and
        // kept translucent so the background shows through -> reads as a glow.
        float glow =
            ringAlpha(1.0) * 1.00 +
            ringAlpha(2.0) * 0.70 +
            ringAlpha(3.0) * 0.45 +
            ringAlpha(4.0) * 0.24;
        glow = glow / 2.39;                     // normalize to ~0..1
        glow = smoothstep(0.03, 0.85, glow);    // soften the edge

        float a = glow * (0.28 + 0.42 * pulse); // translucent, pulsing (max ~0.5)
        if (a < 0.01) discard;

        // Slightly brighten toward white near the sprite for a cleaner glow.
        vec3 gcol = mix(divine, hi, glow * 0.4);
        gl_FragColor = vec4(gcol, a);
    }
}
