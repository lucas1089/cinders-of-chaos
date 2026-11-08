// Phase 8, track C: the colour grade, vignette and soft glow of the map (game_visualfx: chaos_map_grade.frag, chaos_bloom_extract.frag, chaos_bloom_blur.frag)
// as an image effect of the classic view's camera (MapGradePost). Passes: 0 bright pass, 1 blur (one direction), 2 composite (grade, vignette, glow).
// The numbers are Core/Phase8CFx.cs MapGradeFx; the area mood arrives as _Mood (tint r g b, colour kept change) and _Mood2 (contrast change).
// Lives in Resources/ so a player build includes it without a shader list.
Shader "Chaos/MapGrade"
{
    Properties { _MainTex ("Source", 2D) = "white" {} }
    CGINCLUDE
    #include "UnityCG.cginc"
    sampler2D _MainTex;
    float4 _MainTex_TexelSize;
    sampler2D _GlowTex;
    float4 _Mood;        // rgb: added to the colour, w: added to the colour kept (saturation)
    float4 _Mood2;       // x: added to the contrast factor
    float4 _Params;      // x: grade on (0 or 1), y: glow strength, z: threshold, w: full
    float4 _Dir;         // blur step in uv (x, y)

    struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

    v2f vert (appdata_img v)
    {
        v2f o;
        o.pos = UnityObjectToClipPos(v.vertex);
        o.uv = v.texcoord;
        return o;
    }

    float3 Bright (float2 uv)
    {
        float3 c = tex2D(_MainTex, uv).rgb;
        float l = dot(c, float3(0.299, 0.587, 0.114));
        return c * smoothstep(_Params.z, _Params.w, l);
    }

    float4 fragBright (v2f i) : SV_Target
    {
        float2 o = _MainTex_TexelSize.xy * 2.0;   // half a pixel of the quarter size buffer
        float3 s = Bright(i.uv + float2(-o.x, -o.y)) + Bright(i.uv + float2(o.x, -o.y)) + Bright(i.uv + float2(-o.x, o.y)) + Bright(i.uv + float2(o.x, o.y));
        return float4(s * 0.25, 1.0);
    }

    float4 fragBlur (v2f i) : SV_Target
    {
        float2 d = _Dir.xy;
        float3 s = tex2D(_MainTex, i.uv).rgb * 0.2270270270;
        s += (tex2D(_MainTex, i.uv + d * 1.3846153846).rgb + tex2D(_MainTex, i.uv - d * 1.3846153846).rgb) * 0.3162162162;
        s += (tex2D(_MainTex, i.uv + d * 3.2307692308).rgb + tex2D(_MainTex, i.uv - d * 3.2307692308).rgb) * 0.0702702703;
        return float4(s, 1.0);
    }

    float4 fragComposite (v2f i) : SV_Target
    {
        float4 c = tex2D(_MainTex, i.uv);
        float3 col = c.rgb;
        if (_Params.x > 0.5)
        {
            float l = dot(col, float3(0.299, 0.587, 0.114));
            col = lerp(col, float3(l, l, l), saturate(0.12 - _Mood.w));
            col += float3(-0.010, 0.004, 0.020) * (1.0 - l) + float3(0.024, 0.010, -0.014) * l;
            col += _Mood.xyz;
            col = (col - 0.5) * (1.06 + _Mood2.x) + 0.5;
            float2 n = (i.uv * 2.0 - 1.0) * float2(0.88, 0.95);
            float v = smoothstep(0.50, 1.28, length(n));
            col *= 1.0 - 0.44 * v;
            col = saturate(col);
        }
        if (_Params.y > 0.0)
        {
            // screen blend of the blurred bright pass, weighted by the strength
            float3 g = tex2D(_GlowTex, i.uv).rgb * _Params.y;
            col = 1.0 - (1.0 - col) * (1.0 - saturate(g));
        }
        return float4(col, c.a);
    }
    ENDCG
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass { CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragBright
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragBlur
            ENDCG }
        Pass { CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragComposite
            ENDCG }
    }
    Fallback Off
}
