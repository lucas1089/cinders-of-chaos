// HD-2D post effect (O432): bright-pass, blur, tilt-shift blur mask by screen Y, vignette, warm grade.
// Driven by Hd2dPost.cs (OnRenderImage, built-in pipeline).
Shader "Hidden/Chaos/Hd2dPost"
{
    Properties { _MainTex ("Source", 2D) = "white" {} }
    CGINCLUDE
    #include "UnityCG.cginc"
    sampler2D _MainTex;
    float4 _MainTex_TexelSize;
    sampler2D _BlurTex;     // half resolution, blurred copy of the scene (depth of field)
    sampler2D _BloomTex;    // quarter resolution, blurred bright pixels
    float2 _Dir;            // blur direction in texels
    float _Threshold;
    float _Knee;
    float _BloomIntensity;
    float _DofOn;           // 0 or 1
    float _FocusHalf;       // half height of the sharp band, 0..0.5 of the screen
    float _FocusFeather;    // ramp length to full blur, 0..0.5
    float _Vignette;        // 0..1
    float3 _Tint;           // warm multiply
    float _Saturation;
    float _Contrast;

    float3 Blur9(sampler2D t, float2 uv, float2 texel)
    {
        float2 d = texel * _Dir;
        float3 c = tex2D(t, uv).rgb * 0.2270270;
        c += (tex2D(t, uv + d * 1.3846154).rgb + tex2D(t, uv - d * 1.3846154).rgb) * 0.3162162;
        c += (tex2D(t, uv + d * 3.2307692).rgb + tex2D(t, uv - d * 3.2307692).rgb) * 0.0702703;
        return c;
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

    fixed4 fragComposite(v2f_img i) : SV_Target
    {
        float2 uv = i.uv;
        float3 col = tex2D(_MainTex, uv).rgb;
        if (_DofOn > 0.5)
        {
            float d = abs(uv.y - 0.5);
            float m = saturate((d - _FocusHalf) / max(_FocusFeather, 1e-3));
            m = m * m * (3 - 2 * m);
            col = lerp(col, tex2D(_BlurTex, uv).rgb, m);
        }
        col += tex2D(_BloomTex, uv).rgb * _BloomIntensity;
        float2 q = uv - 0.5;
        float v = saturate(1 - dot(q, q) * 3.2 * _Vignette);
        col *= lerp(1, v, 0.85);
        col *= _Tint;
        float l = dot(col, float3(0.299, 0.587, 0.114));
        col = lerp(float3(l, l, l), col, _Saturation);
        col = (col - 0.5) * _Contrast + 0.5;
        return fixed4(max(col, 0), 1);
    }
    ENDCG
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass { CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment fragBright
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment fragBlur
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment fragComposite
            ENDCG }
    }
    Fallback Off
}
