// Lit, alpha-cutout sprite shader of the HD-2D view (O432): the sprite atlas lit by the scene's point lights (forward, per
// pixel for the nearest ones), casting and receiving shadows through the cutout. Very bright texels (flames, glints) are
// also emissive so the bloom picks them up. Lives in Resources/ so a player build includes it without a shader list.
Shader "Chaos/Hd2dSprite"
{
    Properties
    {
        _MainTex ("Atlas", 2D) = "white" {}
        _Cutoff ("Alpha cutoff", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags { "Queue" = "AlphaTest" "RenderType" = "TransparentCutout" "IgnoreProjector" = "True" }
        Cull Off
        CGPROGRAM
        #pragma surface surf Lambert alphatest:_Cutoff addshadow fullforwardshadows
        sampler2D _MainTex;
        struct Input { float2 uv_MainTex; };
        void surf (Input IN, inout SurfaceOutput o)
        {
            fixed4 c = tex2D(_MainTex, IN.uv_MainTex);
            o.Albedo = c.rgb;
            o.Alpha = c.a;
            half lum = max(c.r, max(c.g, c.b));
            o.Emission = c.rgb * saturate((lum - 0.8) * 5.0);
        }
        ENDCG
    }
    FallBack "Legacy Shaders/Transparent/Cutout/VertexLit"
}
