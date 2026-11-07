// Spell art of the front-art scene (Unity/FrontArtScene.cs): missiles and impacts as camera-facing quads. The picture's colour
// times its alpha, brightened by _Boost so the bloom catches it, over the frame (premultiplied: Blend One OneMinusSrcAlpha), no
// depth write. _MainTex_ST picks the animation frame (and a missile's direction row). _Tint multiplies the colour (white = as drawn), its alpha
// is the opacity (Unity/FrontLiveFx.cs sets both per quad through a MaterialPropertyBlock).
// Lives in Resources/ so a player build includes it without a shader list.
Shader "Chaos/FrontArtSpell"
{
    Properties
    {
        _MainTex ("Art", 2D) = "white" {}
        _Boost ("Brightness", Float) = 1.6
        _Tint ("Tint (rgb multiplies, a is opacity)", Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags { "Queue" = "Transparent+20" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Blend One OneMinusSrcAlpha
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
            float4 _MainTex_ST;
            float _Boost;
            float4 _Tint;
            struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }
            float4 frag (v2f i) : SV_Target
            {
                float4 c = tex2D(_MainTex, i.uv);
                float a = c.a * _Tint.a;   // premultiplied: the opacity scales colour and alpha
                return float4(c.rgb * _Tint.rgb * a * _Boost, a);
            }
            ENDCG
        }
    }
}
