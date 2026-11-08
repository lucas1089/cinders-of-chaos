// Phase 8, track C: the sprite shader of the classic map (MapView), a drop-in for Sprites/Default. Vertex colour times the atlas texel, premultiplied alpha.
// The second UV channel (x mode, y strength 0..1, zw the cell's lower left corner in the atlas) switches one quad to an effect of ChaosFx.cginc:
// outfit shaders (game_chaosshaders), hit flash and outline silhouettes (game_visualfx, game_cosmeticfx), living water and lava (game_visualfx).
// Mode 0 is the plain sprite, so a mesh that carries no modes draws exactly as before. Lives in Resources/ so a player build includes it without a shader list.
Shader "Chaos/MapFx"
{
    Properties
    {
        _MainTex ("Atlas", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "IgnoreProjector" = "True" "RenderType" = "Transparent" "PreviewType" = "Plane" }
        Cull Off
        Lighting Off
        ZWrite Off
        Blend One OneMinusSrcAlpha
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            #include "ChaosFx.cginc"

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;

            struct appdata { float4 vertex : POSITION; fixed4 color : COLOR; float2 uv : TEXCOORD0; float4 fx : TEXCOORD1; };
            struct v2f { float4 pos : SV_POSITION; fixed4 color : COLOR; float2 uv : TEXCOORD0; float4 fx : TEXCOORD1; };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.color = v.color;
                o.uv = v.uv;
                o.fx = v.fx;
                return o;
            }

            // a neighbouring texel, kept inside the 32 x 32 cell (the atlas holds other sprites next to it)
            float4 Near (float2 uv, float2 lo, float2 hi) { return tex2D(_MainTex, clamp(uv, lo, hi)); }

            fixed4 frag (v2f i) : SV_Target
            {
                int mode = (int)(i.fx.x + 0.5);
                float4 c;
                if (mode == 0)
                {
                    c = tex2D(_MainTex, i.uv) * i.color;
                    c.rgb *= c.a;
                    return c;
                }
                float2 texel = _MainTex_TexelSize.xy;
                float cell = texel.x * 32.0;
                float2 cellMin = i.fx.zw;
                float2 cellUv = saturate((i.uv - cellMin) / cell);
                float2 lo = cellMin + texel * 0.5;
                float2 hi = cellMin + cell - texel * 0.5;
                if (mode == FX_WATER || mode == FX_LAVA)
                {
                    float2 norm = cellUv * 2.0 - 1.0;
                    c = tex2D(_MainTex, clamp(i.uv + FxLiquidShift(mode, norm, texel, _Time.y), lo, hi));
                    c.rgb = saturate(c.rgb * FxLiquidGain(mode, norm, _Time.y));
                    c *= i.color;
                    c.rgb *= c.a;
                    return c;
                }
                c = tex2D(_MainTex, i.uv);
                float n = min(min(Near(i.uv + float2(texel.x, 0), lo, hi).a, Near(i.uv - float2(texel.x, 0), lo, hi).a),
                              min(Near(i.uv + float2(0, texel.y), lo, hi).a, Near(i.uv - float2(0, texel.y), lo, hi).a));
                float rim = 1.0 - n;
                float2 px = i.uv / texel;
                float4 r = FxApply(i.fx.x, i.fx.y, c, px, cellUv, rim, i.color, _Time.y);
                r.rgb *= r.a;
                return fixed4(r);
            }
            ENDCG
        }
    }
    Fallback "Sprites/Default"
}
