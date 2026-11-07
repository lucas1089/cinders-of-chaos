// Soft procedural shadows on the floor of the HD-2D view (O432): contact blobs under things and ambient occlusion along the
// foot of walls. Unlit, alpha blended black over the floor; drawn after the cutout queues so floor, decals and borders are
// below and the upright sprites cover it through the depth test. uv.z: 0 blob (radial), 1 wall strip; uv.w: strength.
Shader "Chaos/Hd2dBlob"
{
    Properties { }
    SubShader
    {
        Tags { "Queue" = "Transparent-10" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off
        Offset -1, -1
        Pass
        {
            CGPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata { float4 vertex : POSITION; float4 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float4 uv : TEXCOORD0; };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float a;
                if (i.uv.z < 0.5)
                {
                    float2 d = (i.uv.xy - 0.5) * 2.0;
                    float r = saturate(1.0 - dot(d, d));   // 1 in the middle, 0 on the rim
                    a = r * r * (3.0 - 2.0 * r);
                }
                else
                {
                    float fall = saturate(i.uv.y);   // 1 at the wall, 0 away from it
                    a = fall * fall;   // no fade along the wall: neighbouring strips meet without a seam
                }
                return fixed4(0.02, 0.01, 0.03, a * i.uv.w);
            }
            ENDCG
        }
    }
}
