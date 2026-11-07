// HD-2D post effect (O432): bright-pass, blur, light shafts, two-level tilt-shift blur by screen Y, ACES tonemap,
// split-toned grade with lifted blacks, tinted vignette, light grain.
// Driven by Hd2dPost.cs (OnRenderImage, built-in pipeline). Passes: 0 bright, 1 blur, 2 composite, 3 shafts.
Shader "Hidden/Chaos/Hd2dPost"
{
    Properties { _MainTex ("Source", 2D) = "white" {} }
    CGINCLUDE
    #include "UnityCG.cginc"
    sampler2D _MainTex;
    float4 _MainTex_TexelSize;
    sampler2D _BlurTex;     // half resolution, lightly blurred copy of the scene (depth of field, near the focus band)
    sampler2D _BlurTex2;    // quarter resolution, heavily blurred copy (depth of field, far from the focus band)
    sampler2D _BloomTex;    // quarter resolution, blurred bright pixels
    sampler2D _ShaftTex;    // quarter resolution, light shafts (pass 3)
    float2 _Dir;            // blur direction in texels
    float _Threshold;
    float _Knee;
    float _BloomIntensity;
    float _DofOn;           // 0 or 1
    float _ShaftOn;         // 0 or 1
    float _FocusHalf;       // half height of the sharp band, 0..0.5 of the screen
    float _FocusFeather;    // ramp length to full blur, 0..0.5
    float _Vignette;        // 0..1
    float3 _Tint;           // overall multiply
    float _Saturation;
    float _MidSat;          // extra saturation on midtones
    float _Contrast;
    float _Exposure;
    float3 _ShadowTint;     // multiply in the shadows (cool)
    float3 _HighlightTint;  // multiply in the highlights (warm)
    float _SplitStrength;   // 0..1
    float3 _Lift;           // added to the blacks, scaled by 1 - colour
    float _Grain;           // amplitude
    float _GrainSeed;
    float4 _ShaftA;         // xy: source in uv, z: strength (0 = off)
    float4 _ShaftB;
    float4 _ShaftColA;      // rgb
    float4 _ShaftColB;
    float _ShaftDecay;
    float _ShaftDensity;    // share of the way to the source that is sampled

    float3 Blur9(sampler2D t, float2 uv, float2 texel)
    {
        float2 d = texel * _Dir;
        float3 c = tex2D(t, uv).rgb * 0.2270270;
        c += (tex2D(t, uv + d * 1.3846154).rgb + tex2D(t, uv - d * 1.3846154).rgb) * 0.3162162;
        c += (tex2D(t, uv + d * 3.2307692).rgb + tex2D(t, uv - d * 3.2307692).rgb) * 0.0702703;
        return c;
    }

    // ACES filmic, fitted (same curve as Core/Hd2dGrade.cs Aces)
    float3 Aces(float3 x)
    {
        return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
    }

    float Hash21(float2 p)
    {
        float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return frac((p3.x + p3.y) * p3.z);
    }

    float3 ShaftFrom(float2 uv, float4 src, float3 colr)
    {
        if (src.z <= 0.0) return float3(0.0, 0.0, 0.0);
        float2 toSrc = src.xy - uv;
        float2 stepv = toSrc * (_ShaftDensity / 20.0);
        float2 p = uv;
        float w = 1.0;
        float3 acc = float3(0.0, 0.0, 0.0);
        for (int k = 0; k < 20; k++)
        {
            p += stepv;
            acc += tex2Dlod(_MainTex, float4(p, 0.0, 0.0)).rgb * w;
            w *= _ShaftDecay;
        }
        float fall = saturate(1.0 - length(toSrc) * 0.9);
        return acc * (1.0 / 20.0) * (fall * fall) * colr * src.z;
    }

    fixed4 fragBright(v2f_img i) : SV_Target
    {
        float3 c = tex2D(_MainTex, i.uv).rgb;
        float br = max(c.r, max(c.g, c.b));
        float soft = clamp(br - _Threshold + _Knee, 0, 2 * _Knee);
        soft = soft * soft / (4 * _Knee + 1e-4);
        float w = max(soft, br - _Threshold) / max(br, 1e-4);
        return fixed4(c * w, 1);
    }

    fixed4 fragBlur(v2f_img i) : SV_Target
    {
        return fixed4(Blur9(_MainTex, i.uv, _MainTex_TexelSize.xy), 1);
    }

    fixed4 fragShafts(v2f_img i) : SV_Target
    {
        float3 s = ShaftFrom(i.uv, _ShaftA, _ShaftColA.rgb) + ShaftFrom(i.uv, _ShaftB, _ShaftColB.rgb);
        return fixed4(s, 1);
    }

    fixed4 fragComposite(v2f_img i) : SV_Target
    {
        float2 uv = i.uv;
        float3 col = tex2D(_MainTex, uv).rgb;

        // tilt-shift: sharp band, then a light blur, then a heavy blur, blended by the distance from the band
        if (_DofOn > 0.5)
        {
            float d = abs(uv.y - 0.5);
            float m = saturate((d - _FocusHalf) / max(_FocusFeather, 1e-3));
            m = m * m * (3.0 - 2.0 * m);
            float t = m * 2.0;
            float3 light = tex2D(_BlurTex, uv).rgb;
            float3 heavy = tex2D(_BlurTex2, uv).rgb;
            col = lerp(lerp(col, light, saturate(t)), heavy, saturate(t - 1.0));
        }

        // light added in HDR, before the tonemap
        col += tex2D(_BloomTex, uv).rgb * _BloomIntensity;
        if (_ShaftOn > 0.5) col += tex2D(_ShaftTex, uv).rgb;

        // filmic tonemap
        col = Aces(max(col, 0.0) * _Exposure);

        // grade: lifted blacks, split toning, midtone saturation, contrast
        col = col + _Lift * (1.0 - col);
        float l = dot(col, float3(0.299, 0.587, 0.114));
        float sw = 1.0 - smoothstep(0.0, 0.55, l);
        float hw = smoothstep(0.45, 1.0, l);
        col = lerp(col, col * _ShadowTint, sw * _SplitStrength);
        col = lerp(col, col * _HighlightTint, hw * _SplitStrength);
        col *= _Tint;
        l = dot(col, float3(0.299, 0.587, 0.114));
        float mid = 1.0 - abs(l * 2.0 - 1.0);
        float sat = _Saturation + _MidSat * mid * mid;
        col = lerp(float3(l, l, l), col, sat);
        col = (col - 0.5) * _Contrast + 0.5;

        // vignette, darker and tinted toward the shadow colour
        float2 q = uv - 0.5;
        float vg = saturate(dot(q, q) * 3.2 * _Vignette);
        col *= 1.0 - 0.85 * vg;
        col = lerp(col, col * _ShadowTint, vg * 0.5);

        // film grain, strongest in the mids
        float n = Hash21(uv * _ScreenParams.xy + _GrainSeed) - 0.5;
        col += n * _Grain * (0.4 + 0.6 * mid);

        return fixed4(saturate(col), 1);
    }
    ENDCG
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass { CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment fragBright
            #pragma target 3.0
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment fragBlur
            #pragma target 3.0
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment fragComposite
            #pragma target 3.0
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment fragShafts
            #pragma target 3.0
            ENDCG }
    }
    Fallback Off
}
