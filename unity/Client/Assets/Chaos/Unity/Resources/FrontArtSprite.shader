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
        _BumpMap ("Normal map (OpenGL, linear)", 2D) = "bump" {}
        _NormalAmount ("Normal map amount", Range(0, 1)) = 0
        _EmitTex ("Emission mask (linear)", 2D) = "black" {}
        _EmitAmount ("Emission amount", Range(0, 8)) = 0
        _Cutoff ("Alpha cutoff", Range(0, 1)) = 0.5
        _Wrap ("Wrap", Range(0, 1)) = 0.35
        _Bend ("Bend up", Range(0, 1)) = 0.55
        _Fill ("Warm fill", Range(0, 0.5)) = 0.05
        _PointScale ("Point light scale", Range(0, 1)) = 0.45
        _Hit ("Hit flash", Range(0, 1)) = 0
        _Tint ("Tint (a class colour)", Color) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags { "Queue" = "AlphaTest" "RenderType" = "TransparentCutout" "IgnoreProjector" = "True" }
        Cull Off
        CGPROGRAM
        #pragma target 3.0
        #pragma surface surf FrontSprite alphatest:_Cutoff addshadow fullforwardshadows
        sampler2D _MainTex, _BumpMap, _EmitTex;
        half _NormalAmount, _EmitAmount;
        half _Wrap, _Bend, _Fill, _PointScale, _Hit;
        fixed4 _Tint;

        struct SurfaceOutputFS
        {
            fixed3 Albedo;
            fixed3 Normal;
            half3 Emission;
            half Specular;
            fixed Gloss;
            fixed Alpha;
            half3 N;
        };

        struct Input { float2 uv_MainTex; float3 worldPos; };

        void surf (Input IN, inout SurfaceOutputFS o)
        {
            fixed4 c = tex2Dlod(_MainTex, float4(IN.uv_MainTex, 0, 0));
            c.rgb *= _Tint.rgb;   // a class's tint (the live creatures); white leaves the picture as drawn
            o.Albedo = c.rgb;
            o.Alpha = c.a;
            float3 toCam = normalize(_WorldSpaceCameraPos - IN.worldPos);
            float3 bent = normalize(lerp(toCam, float3(0, 1, 0), _Bend));
            // the picture's own normal map (right, up, toward the viewer) on the quad's axes: a head is round, a shield faces out, so
            // a flame beside the figure lights one side of it, the way a lit 3D body would
            half3 tn = tex2Dlod(_BumpMap, float4(IN.uv_MainTex, 0, 0)).xyz * 2.0 - 1.0;
            float3 R = normalize(mul((float3x3)unity_ObjectToWorld, float3(1, 0, 0)));
            float3 U = normalize(mul((float3x3)unity_ObjectToWorld, float3(0, 1, 0)));
            float3 F = normalize(mul((float3x3)unity_ObjectToWorld, float3(0, 0, -1)));
            float3 wn = normalize(tn.x * R + tn.y * U + tn.z * F + float3(0, 0.35 * _Bend, 0));
            o.N = normalize(lerp(bent, wn, _NormalAmount));
            half3 amb = ShadeSH9(half4(o.N, 1));
            o.Emission = c.rgb * (amb + _Fill * half3(1.0, 0.9, 0.8));
            // the glowing parts (a staff flame, eyes; unity/tools/gen_front_art_emission.py) light themselves, past 1 so the bloom takes them
            o.Emission += c.rgb * tex2Dlod(_EmitTex, float4(IN.uv_MainTex, 0, 0)).r * _EmitAmount;
            // struck by a melee blow (FrontArtMelee.Flinch): a red-white flash over the picture
            o.Emission = lerp(o.Emission, (0.35 + c.rgb) * half3(2.0, 0.55, 0.45), _Hit * 0.7);
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
