uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;

uniform vec2 u_Resolution;
uniform float u_Time;
#define pi 3.1415926535897932384626433832795
#define S(a, b, t) smoothstep(a, b, t)

// Config --------------------------
#define LINEWIDTH .1
#define SCALE 75.
#define DOTSIZE 12.
#define STARTSCOLOR vec3(.1, .6, 1.);
// ----------------------------------





float DistLine(vec2 p, vec2 a, vec2 b)
{
    vec2 pa = p-a;
    vec2 ba = b-a;
    float t = clamp(dot(pa, ba)/dot(ba, ba), 0., 1.);
    return length(pa - ba*t);
}

float N21(vec2 p)
{
    p = fract(p * vec2(215.33, 817.23));
    p += dot(p, p+ 25.24);
    return fract(p.x * p.y);
}

vec2 N22(vec2 p)
{
    float n = N21(p);
    return vec2(n, N21(p+n));
}

vec2 GetPos(vec2 id, vec2 offset)
{
    vec2 n = N22(id + offset) * u_Time;
    return offset+sin(n)*.9;
}

float Line(vec2 p, vec2 a, vec2 b)
{
	float d = DistLine(p, a, b);
    float m = S(LINEWIDTH, .01, d);
    float d2 = length(a-b);
    m *= S(1.6, .3, d2)*.5 + S(.05, .01, abs(d2-.75));
    
    return m;
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
   vec2 coord = (gl_FragCoord.xy / u_Resolution.xy);
	vec3 colorRing = vec3(0.0);
	vec2 translate = vec2(-0.5);
	
    vec2 uv = (gl_FragCoord -.5 *u_Resolution.xy) / u_Resolution.y;
	
    float m = 0.;
    uv *= SCALE;
    
    vec2 gv = fract(uv) - .5;
    vec2 id = floor(uv);
    
    vec2 p[9];
    int i = 0;
    for(float y=-1.; y<=1.; y++)
    {
        for(float x=-1.; x<=1.; x++)
    	{
    		p[i++] = GetPos(id, vec2(x, y));
        }
    }
    
    float t = u_Time*10.;
    for (int i=0; i<9; i++)
    {
        m += Line(gv, p[4], p[i]);
        
        vec2 j = (p[i]-gv) * DOTSIZE;
        float sparkle = 1./ dot(j, j);
        m += sparkle * (sin(t+fract(p[i].x)*10.) * .5 + .5);
    }
    
    m += Line(gv, p[1], p[3]);
    m += Line(gv, p[1], p[5]);
    m += Line(gv, p[7], p[3]);
    m += Line(gv, p[7], p[5]);
    
    vec3 col = vec3(m);
    vec3 starsColor = STARTSCOLOR;
    col *= starsColor; 
    
	
	vec4 darker = texcolorMain;
	vec4 overlaper = mix( darker, vec4 ( col, 0.4 ), darker.a );
	gl_FragColor = overlaper * overlaper.a + texcolorMain * (1.0 - overlaper.a);
    //Output to screen
}