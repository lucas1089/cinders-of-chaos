uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;

uniform vec2 u_Resolution;
uniform float u_Time;


float random(vec2 v) {
    return fract(sin(v.x * 32.1231 - v.y * 2.334 + 13399.2312) * 2412.32312);
}
float random(float x, float y) {
    return fract(sin(x * 32.1231 - y * 2.334 + 13399.2312) * 2412.32312);
}
float random(float x) {
    return fract(sin(x * 32.1231 + 13399.2312) * 2412.32312);
}

float hue2rgb(float f1, float f2, float hue) {
    if (hue < 0.0)
        hue += 1.0;
    else if (hue > 1.0)
        hue -= 1.0;
    float res;
    if ((6.0 * hue) < 1.0)
        res = f1 + (f2 - f1) * 6.0 * hue;
    else if ((2.0 * hue) < 1.0)
        res = f2;
    else if ((3.0 * hue) < 2.0)
        res = f1 + (f2 - f1) * ((2.0 / 3.0) - hue) * 6.0;
    else
        res = f1;
    return res;
}
vec3 hsl2rgb(vec3 hsl) {
    vec3 rgb;
    
    if (hsl.y == 0.0) {
        rgb = vec3(hsl.z); // Luminance
    } else {
        float f2;
        
        if (hsl.z < 0.5)
            f2 = hsl.z * (1.0 + hsl.y);
        else
            f2 = hsl.z + hsl.y - hsl.y * hsl.z;
            
        float f1 = 2.0 * hsl.z - f2;
        
        rgb.r = 0.0; // hue2rgb(f1, f2, hsl.x + (1.0/3.0));
        rgb.g = cos( hue2rgb(f1, f2, hsl.x ));
        rgb.b = 0.0; // hue2rgb(f1, f2, hsl.x - (1.0/3.0));
    }   
    return rgb;
}

float character(float i) {    
     return i<15.01? floor(random(i)*32768.) : 0.;
}

void main()
{
    vec4 texcolorMain = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    if(texcolor.r > 0.9) {
        texcolorMain *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        texcolorMain *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        texcolorMain *= u_Color[3];
    }
	vec3 colorRing = vec3(0.0);
	vec2 translate = vec2(-0.5);
	

    vec2 S = 15. * vec2(3., 2.);
    vec2 coord = vec2(
        gl_FragCoord.x / u_Resolution.y,
        gl_FragCoord.y / u_Resolution.y + (u_Resolution.y - u_Resolution.x) / (9. * u_Resolution.y)
    );
	coord *= 5.0;
    vec2 c = floor(coord * S);

    float offset = random(c.x) * S.x;
    float speed = random(c.x * 3.) * 1. + 0.2;
	speed *= 0.6;
    float len = random(c.x) * 15. + 10.;
    float u = 1. - fract(c.y / len + u_Time * speed + offset) * 2.;

    float padding = 2.;
    vec2 smS = vec2(3., 5.);
    vec2 sm = floor(fract(coord * S) * (smS + vec2(padding))) - vec2(padding);
    float symbol = character(floor(random(c + floor(u_Time * speed)) * 15.));
    bool s = sm.x < 0. || sm.x > smS.x || sm.y < 0. || sm.y > smS.y ? false
             : mod(floor(symbol / pow(2., sm.x + sm.y * smS.x)), 2.) == 1.;

    vec3 curRGB = hsl2rgb(vec3(c.x / S.x, 1., 0.5));
    if( s )
    {
        if( u > 0.9 )
            {
            curRGB.r = 1.0;
            curRGB.g = 1.0;
            curRGB.b = 1.0;
            }
        else
            curRGB = curRGB * u;
    }
    else
        curRGB = vec3( 0.0, 0.0, 0.0 );

        
	vec4 darker = texcolorMain;
	vec4 overlaper = mix(darker, vec4(curRGB.x, curRGB.y, curRGB.z, 0.2), darker.a);
	gl_FragColor = overlaper * overlaper.a + texcolorMain * (1.0 - overlaper.a);
	
}