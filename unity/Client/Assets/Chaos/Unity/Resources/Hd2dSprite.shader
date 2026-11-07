// Lit, alpha-cutout sprite shader of the HD-2D view (O432): the sprite atlas lit by the scene's point lights (forward, per
// pixel for the nearest ones), casting and receiving shadows through the cutout. Very bright texels (flames, glints) are
// also emissive so the bloom picks them up. Lives in Resources/ so a player build includes it without a shader list.
// Volume (upright sprites only; floor quads are left flat): a fake normal from the alpha edge and the luminance gradient of
// the 32 x 32 cell tilts the lit side, a rim term lets silhouettes catch each light, and the foot of a sprite is darkened by
// the world height (ground bounce / occlusion). Neighbour texels are clamped inside the cell: the atlas holds other sprites
// next to it.
Shader "Chaos/Hd2dSprite"
{
    Properties
    {
        _MainTex ("Atlas", 2D) = "white" {}
        _Cutoff ("Alpha cutoff", Range(0, 1)) = 0.5
        _Bump ("Edge normal strength", Range(0, 2)) = 0.8
        _Rim ("Rim light", Range(0, 2)) = 0.7
        _FootDark ("Foot darkening", Range(0, 1)) = 0.3
        _FootHeight ("Foot height (world)", Range(0.1, 2)) = 0.8
    }
    SubShader
    {
        Tags { "Queue" = "AlphaTest" "RenderType" = "TransparentCutout" "IgnoreProjector" = "True" }
        Cull Off
        CGPROGRAM
        #pragma target 3.0
        #pragma surface surf Hd2d alphatest:_Cutoff addshadow fullforwardshadows
        sampler2D _MainTex;
        float4 _MainTex_TexelSize;
        half _Bump, _Rim, _FootDark, _FootHeight;

        struct SurfaceOutputHd2d
        {
            fixed3 Albedo;
            fixed3 Normal;
            fixed3 Emission;
            half Specular;
            fixed Gloss;
            fixed Alpha;
            half4 Edge;   // xy: outward edge direction (screen plane), z: rim mask, w: 0
        };

        struct Input { float2 uv_MainTex; float3 worldPos; float3 worldNormal; };

        half Lum (fixed3 c) { return dot(c, fixed3(0.3, 0.59, 0.11)); }

        void surf (Input IN, inout SurfaceOutputHd2d o)
        {
            float2 uv = IN.uv_MainTex;
            fixed4 c = tex2D(_MainTex, uv);

            // the 32 x 32 cell of this texel; neighbours are clamped to stay inside it
            float cells = _MainTex_TexelSize.z / 32.0;
            float2 cellMin = floor(uv * cells) / cells;
            float2 cellSize = float2(1.0 / cells, 1.0 / cells);
            float2 tx = _MainTex_TexelSize.xy;
            float2 lo = cellMin + tx * 0.5;
            float2 hi = cellMin + cellSize - tx * 0.5;
            fixed4 cl = tex2D(_MainTex, clamp(uv + float2(-tx.x, 0), lo, hi));
            fixed4 cr = tex2D(_MainTex, clamp(uv + float2( tx.x, 0), lo, hi));
            fixed4 cd = tex2D(_MainTex, clamp(uv + float2(0, -tx.y), lo, hi));
            fixed4 cu = tex2D(_MainTex, clamp(uv + float2(0,  tx.y), lo, hi));

            // upright quads face the camera (normal y < 0.8); floor quads face up and stay flat
            float upright = 1.0 - smoothstep(0.8, 0.9, abs(IN.worldNormal.y));

            // alpha edge: outward points to the lower alpha. Luminance: the dark side of a ridge tilts away.
            float2 aEdge = float2(cl.a - cr.a, cd.a - cu.a) * 0.5;
            float2 lEdge = float2(Lum(cl.rgb) - Lum(cr.rgb), Lum(cd.rgb) - Lum(cu.rgb)) * 0.5 * c.a;
            float2 e = aEdge + lEdge * 0.6;
            float el = length(e);
            if (el > 1.0) e /= el;

            o.Albedo = c.rgb;
            o.Alpha = c.a;
            half lum = max(c.r, max(c.g, c.b));
            o.Emission = c.rgb * saturate((lum - 0.8) * 5.0);

            // ground bounce / occlusion: darker near the floor (world height), not for floor quads
            float foot = smoothstep(0.0, _FootHeight, IN.worldPos.y);
            o.Albedo *= lerp(1.0, lerp(1.0 - _FootDark, 1.0, foot), upright);

            o.Edge = half4(e * _Bump * upright, saturate(length(aEdge) * 2.0) * c.a * upright, 0);
        }

        half4 LightingHd2d (SurfaceOutputHd2d s, half3 lightDir, half atten)
        {
            // the edge tilts the normal: right-facing edges (x) and up-facing edges (y) turn towards their light
            half3 n = normalize(s.Normal + half3(s.Edge.x, s.Edge.y, 0));
            half diff = saturate(dot(n, lightDir));
            half3 col = s.Albedo * _LightColor0.rgb * diff;
            // rim: a silhouette edge catches the light that comes from its outward side, a little warm
            half3 rn = normalize(half3(s.Edge.x, s.Edge.y, 0.25));
            half rim = s.Edge.z * saturate(dot(rn, lightDir));
            col += (s.Albedo * 0.5 + 0.35) * _LightColor0.rgb * half3(1.0, 0.9, 0.75) * (rim * rim * _Rim);
            half4 c;
            c.rgb = col * atten;
            c.a = s.Alpha;
            return c;
        }
        ENDCG
    }
    FallBack "Legacy Shaders/Transparent/Cutout/VertexLit"
}
