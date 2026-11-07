// Ground shadow of a front-art figure (test of a new look, Unity/FrontArtScene.cs): the figure's own picture laid flat on the floor
// and stretched away from a light, drawn as a dark see-through silhouette. It does not use the shadow map, so it looks the same on
// every machine. The vertex colour's alpha is the strength; the far end fades. Lives in Resources/ so a player build includes it.
Shader "Chaos/FrontArtCast"
{
    Properties
    {
        _MainTex ("Sprite", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "Queue" = "Transparent-10" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            Offset -1, -1
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            sampler2D _MainTex;
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
                return fixed4(0.02, 0.015, 0.04, i.color.a * (1.0 - 0.6 * i.uv.y));
            }
            ENDCG
        }
    }
}
