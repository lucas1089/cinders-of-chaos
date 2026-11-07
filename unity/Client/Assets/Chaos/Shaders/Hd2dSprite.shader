// Sprite billboard for HD-2D (O432): lit by the scene lights (torch point lights), alpha cutout, casts and
// receives shadows. The atlas is sampled at mip 0, so point filtering stays crisp at any distance.
Shader "Chaos/Hd2dSprite"
{
    Properties
    {
        _MainTex ("Atlas", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)
        _Cutoff ("Alpha cutoff", Range(0,1)) = 0.5
        _Glow ("Glow", Range(0,2)) = 0
    }
    SubShader
    {
        Tags { "Queue"="AlphaTest" "RenderType"="TransparentCutout" "IgnoreProjector"="True" }
        Cull Off
        CGPROGRAM
        #pragma surface surf Lambert addshadow fullforwardshadows
        #pragma target 3.0
        sampler2D _MainTex;
        fixed4 _Color;
        half _Cutoff;
        half _Glow;
        struct Input { float2 uv_MainTex; };
        void surf(Input IN, inout SurfaceOutput o)
        {
            fixed4 c = tex2Dlod(_MainTex, float4(IN.uv_MainTex, 0, 0)) * _Color;
            clip(c.a - _Cutoff);
            o.Albedo = c.rgb;
            o.Emission = c.rgb * _Glow;
            o.Alpha = c.a;
        }
        ENDCG
    }
    Fallback "Transparent/Cutout/Diffuse"
}
