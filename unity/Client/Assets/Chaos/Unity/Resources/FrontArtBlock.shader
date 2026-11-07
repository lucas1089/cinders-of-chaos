// Block shader of the front-art scene (test of a new look): the diorama's terrain and props. Texture sampled with the mesh's world
// mapped uv (16 texels per unit, point filtered by the texture), a relief from the height-made normal map tilted per face axis,
// vertex colour as tint and baked ambient occlusion, and a plain lambert light with the sun's shadows and the point lights.
// Ambient (the scene's trilight) is added as emission by hand: a custom lighting function gets no ambient from the compiler.
// _Emit makes a texture glow in its own colours (coals). Lives in Resources/ so a player build includes it without a shader list.
Shader "Chaos/FrontArtBlock"
{
    Properties
    {
        _MainTex ("Albedo", 2D) = "white" {}
        _BumpTex ("Relief (tangent normal)", 2D) = "bump" {}
        _Relief ("Relief strength", Range(0, 2)) = 0.9
        _Emit ("Emission", Range(0, 4)) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        CGPROGRAM
        #pragma target 3.0
        #pragma surface surf FrontArt addshadow
        sampler2D _MainTex;
        sampler2D _BumpTex;
        half _Relief, _Emit;

        struct SurfaceOutputFA
        {
            fixed3 Albedo;
            fixed3 Normal;
            fixed3 Emission;
            half Specular;
            fixed Gloss;
            fixed Alpha;
            half3 N;   // the lit normal, world space
        };

        struct Input { float2 uv_MainTex; float3 worldNormal; float4 color : COLOR; };

        void surf (Input IN, inout SurfaceOutputFA o)
        {
            fixed4 c = tex2D(_MainTex, IN.uv_MainTex);
            float3 n = normalize(IN.worldNormal);
            float2 b = tex2D(_BumpTex, IN.uv_MainTex).xy * 2.0 - 1.0;
            float3 an = abs(n);
            float3 t = float3(0, 0, 0);
            // the uv runs along the world axes of the face: top (x, z), faces to the north and south (x, y), to the east and west (z, y)
            if (an.y > 0.9) t = float3(b.x, 0, b.y);
            else if (an.z > 0.9) t = float3(b.x, b.y, 0);
            else if (an.x > 0.9) t = float3(0, b.y, b.x);
            o.N = normalize(n + t * _Relief);
            o.Albedo = c.rgb * IN.color.rgb;
            o.Alpha = 1;
            half3 amb = ShadeSH9(half4(o.N, 1));
            o.Emission = o.Albedo * amb + c.rgb * _Emit;
        }

        half4 LightingFrontArt (SurfaceOutputFA s, half3 lightDir, half atten)
        {
            half d = saturate(dot(s.N, lightDir));
            half4 c;
            c.rgb = s.Albedo * _LightColor0.rgb * (d * atten);
            c.a = 1;
            return c;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
