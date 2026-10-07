varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform sampler2D u_Tex3;
uniform float u_var0;
uniform float u_Time;
uniform vec2 u_Center;
varying vec2 v_Position;

#define RES 48
#define _Lightness 2.0

float oetf_sRGB_scalar(float L) {
    float V = 1.055 * (pow(L, 1.0 / 2.4)) - 0.055;

    if (L <= 0.0031308)
        V = L * 12.92;

    return V;
}

vec4 oetf_sRGB(vec4 L) {
    return vec4(oetf_sRGB_scalar(L.r), oetf_sRGB_scalar(L.g), oetf_sRGB_scalar(L.b), oetf_sRGB_scalar(L.a));
}

float eotf_sRGB_scalar(float V) {
    float L = pow((V + 0.055) / 1.055, 2.4);

    if (V <= oetf_sRGB_scalar(0.0031308))
        L = V / 12.92;

    return L;
}

int getDistance(vec2 point) {
    return int(sqrt(point.x*point.x + point.y*point.y));
}

vec4 eotf_sRGB(vec4 V) {
    return vec4(eotf_sRGB_scalar(V.r), eotf_sRGB_scalar(V.g), eotf_sRGB_scalar(V.b), eotf_sRGB_scalar(V.a));
}

void main()
{
    if (abs(1.0 - v_TexCoord.y) > u_var0) {
        discard;
    }
    vec4 color = texture2D(u_Tex0, v_TexCoord);

    if (color.a < 0.01) discard; 
    float k = -0.15;
    float _Distortion = 8.0;

    float r2 = (v_TexCoord.x - 0.5) * (v_TexCoord.x - 0.5) + (v_TexCoord.y - 0.5) * (v_TexCoord.y - 0.5);
    float f = 0.0;

    if (_Distortion == 0.0) {
        f = 1.0 + r2 * k;
    }
    else {
        f = 1.0 + r2 * (k + _Distortion * sqrt(r2));
    };

    if (getDistance(v_Position) >= 50) {
        //discard;
    }

    float x = f * (v_TexCoord.x - 0.5) + 0.5;
    float y = f * (v_TexCoord.y - 0.5) + 0.5;
    vec4 u_Tex0_TexelSize = vec4(1 / 256, 1 / 256, 256, 256);
    //vec4 u_Tex1_TexelSize = vec4(1 / 20, 1 / 216, 20, 216);
    vec4 u_Tex2_TexelSize = vec4(1 / 256, 1 / 216, 256, 216);

    float speed = 0.15;

    vec4 layer1 = texture2D(u_Tex0, vec2(x, y));
    vec4 layer2 = texture2D(u_Tex1, vec2(x, y) + vec2(0, u_Tex0_TexelSize.y - u_Time / (2.0/speed)));
    vec4 layer3 = texture2D(u_Tex2, vec2(v_TexCoord.x, v_TexCoord.y));     // + vec2(u_Tex2_TexelSize.x - u_Time / (3.0/speed), u_Tex2_TexelSize.y - u_Time / (4.0/speed));

    //if(color.a < 1) {
    //    layer1.a = 0;
    //    layer2.a = 0;
    //    layer3.a = 0;
    //}

    if (layer3.a > 0.0) {
        //discard;
    }

    //color = mix(color, layer1, 0.5);
    color = mix(color, layer2, 0.5);
    //color = mix(color, layer3, 0.5);
    color.rgb = color.rgb * eotf_sRGB(color).rgb * _Lightness;
	
    gl_FragColor = color;

	if(gl_FragColor.a < 0.01) {
		discard;
	}
	
}