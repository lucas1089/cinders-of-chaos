// Upright character sprite of the front-art scene (test of a new look): a small front-facing picture on a quad that turns with the
// camera's yaw. Alpha cutout, sampled at mip 0 (the pixels stay crisp). Lit with a bent normal (between the direction to the
// camera and straight up, so the figure takes light like a rounded body, not like a flat card), a wrap diffuse (the dark side is
// never black) and a small warm fill. Receives the scene's shadows. The same material on a quad that faces the sun, drawn in
// the shadow pass only (ShadowCastingMode.ShadowsOnly), casts the character's shadow: see Unity/FrontArtScene.cs.
// Lives in Resources/ so a player build includes it without a shader list.
Shader "Chaos/FrontArtSprite"
{
    Properties
    {
        _MainTex ("Sprite", 2D) = "white" {}
        _Cutoff ("Alpha cutoff", Range(0, 1)) = 0.5
        _Wrap ("Wrap", Range(0, 1)) = 0.5
        _Bend ("Bend up", Range(0, 1)) = 0.55
        _Fill ("Warm fill", Range(0, 0.5)) = 0.05
        _PointScale ("Point light scale", Range(0, 1)) = 0.45
    }
    SubShader
    {
        Tags { "Queue" = "AlphaTest" "RenderType" = "TransparentCutout" "IgnoreProjector" = "True" }
        Cull Off
        CGPROGRAM
        #pragma target 3.0
        #pragma surface surf FrontSprite alphatest:_Cutoff addshadow
        sampler2D _MainTex;
        half _Wrap, _Bend, _Fill, _PointScale;

        struct SurfaceOutputFS
        {
            fixed3 Albedo;
            fixed3 Normal;
            fixed3 Emission;
            half Specular;
            fixed Gloss;
            fixed Alpha;
            half3 N;
        };

        struct Input { float2 uv_MainTex; float3 worldPos; };

        void surf (Input IN, inout SurfaceOutputFS o)
        {
            fixed4 c = tex2Dlod(_MainTex, float4(IN.uv_MainTex, 0, 0));
            o.Albedo = c.rgb;
            o.Alpha = c.a;
            float3 toCam = normalize(_WorldSpaceCameraPos - IN.worldPos);
            o.N = normalize(lerp(toCam, float3(0, 1, 0), _Bend));
            half3 amb = ShadeSH9(half4(o.N, 1));
            o.Emission = c.rgb * (amb + _Fill * half3(1.0, 0.9, 0.8));
        }

        half4 LightingFrontSprite (SurfaceOutputFS s, half3 lightDir, half atten)
        {
            half d = saturate((dot(s.N, lightDir) + _Wrap) / (1.0 + _Wrap));
            half4 c;
            half3 l = _LightColor0.rgb * (d * atten);
            #if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
            // a flame facing the picture lights all of it at once (a card has no turned-away side): scale it down and roll off the
            // top so a figure next to a brazier keeps its colours instead of burning to white
            l *= _PointScale;
            l = l / (1.0 + 0.6 * l);
            #endif
            c.rgb = s.Albedo * l;
            c.a = s.Alpha;
            return c;
        }
        ENDCG
    }
    FallBack "Legacy Shaders/Transparent/Cutout/VertexLit"
}
