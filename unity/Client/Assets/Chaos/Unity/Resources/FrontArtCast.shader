// Ground shadow of a front-art figure (test of a new look, Unity/FrontArtScene.cs): the figure's own picture laid flat on the floor
// and stretched away from a light, drawn as a dark see-through silhouette. It does not use the shadow map, so it looks the same on
// every machine. Multiplied into the frame (no alpha blending): _Strength darkens, the far end fades. Lives in Resources/ so a player build includes it.
Shader "Chaos/FrontArtCast"
{
    Properties
    {
        _MainTex ("Sprite", 2D) = "white" {}
        _Strength ("Strength", Range(0, 1)) = 0.5
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4
    }
    SubShader
    {
        Tags { "Queue" = "AlphaTest-50" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            Blend DstColor Zero
            ZWrite Off
            ZTest [_ZTest]
            Cull Off
            Offset -4, -4
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            half _Strength;
            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; fixed4 color : COLOR; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; fixed4 color : COLOR; };
            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                o.color = v.color;
                return o;
            }
            fixed4 frag (v2f i) : SV_Target
            {
                fixed a = tex2Dlod(_MainTex, float4(i.uv, 0, 0)).a;
                clip(a - 0.5);
                half s = _Strength * (1.0 - 0.6 * i.uv.y);
                return fixed4(lerp(half3(1, 1, 1), half3(0.10, 0.08, 0.16), s), 1);
            }
            ENDCG
        }
    }
}
