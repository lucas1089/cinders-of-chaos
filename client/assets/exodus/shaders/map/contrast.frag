uniform float u_Time;
uniform vec2 u_Resolution;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

// fixed4 frag(v2f IN  ) : SV_Target
// {
 // 	UNITY_SETUP_INSTANCE_ID( IN );
 // 	UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX( IN );
 
 // 	float2 uv_MainTex = IN.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw;
 // 	float4 temp_output_1_0_g33 = tex2D( _MainTex, uv_MainTex );
 
 // 	float3 saferPower5_g33 = max( (temp_output_1_0_g33).rgb , 0.0001 );
 // 	float3 temp_cast_0 = (_Contrast).xxx;
 // 	float4 appendResult4_g33 = (float4(pow( saferPower5_g33 , temp_cast_0 ) , temp_output_1_0_g33.a));
 
 // 	fixed4 c = ( appendResult4_g33 * IN.color );
 // 	c.rgb *= c.a;
 // 	return c;
// }

void main(void)
{
 
 vec4 color=texture2D(u_Tex0,v_TexCoord);
 
 vec3 saferPower5_g33=max(color.rgb,.0001);
 vec3 temp_cast_0=vec3(.5);
 vec4 appendResult4_g33=(vec4(pow(saferPower5_g33,temp_cast_0),color.a));
 
 vec4 c=(appendResult4_g33);
 c.rgb*=c.a;
 
 gl_FragColor=c;
 
}