// Additive soft glow of the HD-2D view (O432): dust motes, embers and flame halos as camera-facing quads. Vertex colour times
// a radial falloff texture, added to the frame (Blend One One), no depth write, depth tested so walls hide them.
// Lives in Resources/ so a player build includes it without a shader list.
Shader "Chaos/Hd2dGlow"
{
    Properties
    {
        _MainTex ("Glow", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "Queue" = "Transparent+10" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Blend One One
        ZWrite Off
        Cull Off
        Lighting Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"
            sampler2D _MainTex;
            struct appdata { float4 vertex : POSITION; fixed4 color : COLOR; float2 texcoord : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; fixed4 color : COLOR; float2 uv : TEXCOORD0; };
            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.color = v.color;
                o.uv = v.texcoord;
                return o;
            }
            fixed4 frag (v2f i) : SV_Target
            {
                fixed g = tex2D(_MainTex, i.uv).r;
                fixed3 c = i.color.rgb * (g * i.color.a);
                return fixed4(c, 1);
            }
            ENDCG
        }
    }
}
