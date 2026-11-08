// Phase 15, track B: additive drawing for the classic view (game_visualfx: glowing spell effects, base patch 0152, and added spell light, base patch 0127).
// Used with Graphics.DrawTexture during an immediate-mode GUI repaint; colour = texture * vertex colour, added onto what is under it by alpha (dst + src * alpha).
// A plain vertex and fragment shader: no surface shader, no _MainTex_ST redeclared. Lives in Resources/ so a player build includes it without a shader list.
Shader "Chaos/Add"
{
    Properties { _MainTex ("Texture", 2D) = "white" {} }
    SubShader
    {
        Tags { "Queue" = "Transparent" "IgnoreProjector" = "True" "RenderType" = "Transparent" }
        Pass
        {
            Blend SrcAlpha One
            ZTest Always
            ZWrite Off
            Cull Off
            Lighting Off
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
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
                return tex2D(_MainTex, i.uv) * i.color;
            }
            ENDCG
        }
    }
    Fallback Off
}
