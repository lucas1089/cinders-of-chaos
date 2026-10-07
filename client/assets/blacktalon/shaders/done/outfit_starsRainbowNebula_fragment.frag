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

#define S(x, y, z) smoothstep(x, y, z)
#define M(t, d) mat2(cos(t * d), sin(t * d), -sin(t * d), cos(t * d))
#define SEED .2831
#define PI acos(-1.)

float hash(float n)
{
    return fract(sin(n) * 91438.55123);   
}

float hash2(vec2 p)
{
	vec3 p3  = fract(vec3(p.xyx) * SEED);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

float noise( in vec2 x ) {
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f*f*(3.0-2.0*f);
    float n = p.x + p.y*57.0;
    return mix(mix( hash(n + 0.0), hash(n + 1.0), f.x), mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y);
}

mat2 m = mat2( 0.6, 0.6, -0.6, 0.8);
float fbm(vec2 p){
 
    float f = 0.0;
    f += 0.5000 * noise(p); p *= m * 2.02;
    f += 0.2500 * noise(p); p *= m * 2.03;
    f += 0.1250 * noise(p); p *= m * 2.01;
    f += 0.0625 * noise(p); p *= m * 2.04;
    f /= 0.9375;
    return f;
}

float star(vec2 uv, vec2 scale, float density){

    
    vec2 grid = uv * scale;
    vec2 id = floor(grid);  
    grid = fract(grid) - .5;

    float d = length(grid);  
    float r = pow(hash2(id), density);
    float star = S(-.01, clamp(r,.0,.5), d);

    return 1. - star ;
}

float halo(vec2 uv, vec2 scale, float density){

    
    vec2 grid = uv * scale;
    vec2 id = floor(grid);  
    grid = fract(grid) - .5;

    float d = length(grid);  
    float r = pow(hash2(id), density);
    float a = S(-.4, clamp(r,.0,.5), d);

    return 1. - a ;
}

float bigstar(vec2 uv, vec2 scale, float density, float angle, float speed){

    //angle *= PI*.5;
    vec2 grid = uv * scale;
    vec2 id = floor(grid);  
    grid = fract(grid) - .5;

    float d = length(grid);  
    float dx = length(M(-angle,speed)*grid*vec2(5.0,.1)); 
    float dy = length(M(-angle,speed)*grid*vec2(.1,5.)); 
    float r = pow(hash2(id), density);
    float star = S(-.01, clamp(r,.0,.3), d);
    
    float l = S(.0, 1.,length(grid-1.));
 

    return   1. - S(-.1,r*l*l, 2.*sqrt(dot(dx,dy)));
}


vec2 dist(vec2 uv){
    
    vec2 d = vec2(.0);
    d += .2*dot(uv,uv)-.5;
    
 return d;   
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
	
	vec2 uv = gl_FragCoord.xy / u_Resolution.xy;
    uv.x *= u_Resolution.x / u_Resolution.y;
    
    uv *= 2.0;
    
    vec2 st = uv * 1.35;
   
    
    st += dist(st);
    float t = u_Time * .01;
    
    uv-= vec2(.8,.5);
    st += sign(dot(uv,uv));
    uv += sign(dot(uv,uv));


    float mw = S(-.5, 1.5, length(uv));
    
    
    float a0 = halo(M( t, 2.5) * uv, vec2(15.), mw * 50.0);
    float l0 = a0+bigstar(M( t, 2.5) * uv, vec2(15.), mw * 50.0,  t , 2.5);
    
    
    
    float l1 = star(M(10.+t, 2.0) * uv * .8, vec2(120.0), mw * 80.0);
    float l2 = star(M(20.+t, 1.5) * uv * .6, vec2(150.), mw * 100.0);
    float l3 = star(M(t*1.4, 1.0) * uv, vec2(200.), mw * 120.0);
    
    float a4 = halo(M(PI+t*1.4, 3.0) * uv, vec2(15.), mw * 90.0);
    float l4 = a4+bigstar(M(PI+t*1.4, 3.) * uv, vec2(15.), mw * 90.0, t * 1.4  , 3.);
    
    uv -= sign(dot(uv,uv));
    
    vec2 n1 = vec2(.2 * t, .2 * t);
    vec2 n2 = vec2(.3 * t, .3 * t);
    vec2 n3 = vec2(.4 * t, .4 * t);
    
    float r = .23 * fbm(M(t, 2.5) * (1.5*st + n1));
    float g = .24 * fbm(M(t, 2.0) * ( 2. * st + n2));
    float b = .26 * fbm(M(t, 1.5) * (1. * st + n3));
    
    vec4 cl = pow(vec4(r, g, b, 1.), vec4(1.3));
    cl = cl + cl;
    
    vec4 s = vec4(vec3(l0 + l1 + l2 + l3 + l4), 1.0);
    cl = pow(cl  + cl , vec4(1.5));
    cl = pow(cl + cl + cl , vec4(1.5))*.7;
 
   
    cl = mix( cl + cl,  cl * s , .85);
 	
    cl += cl * 2.;
    cl.xyz += .5 * pow(1.-length(uv/2.), 2.5);

    cl = .9 * clamp(cl, vec4(.0), vec4(1.));

    cl += S(.0,1.,S(.7, 1.,s));
    float cl1 = fbm((fbm(st*.4) - vec2(t, t )) * 15.) * dist(uv).x;

    
    cl = mix(cl,   cl + cl1+cl1+cl1, .8);
	cl += .33 * fbm( vec2(-u_Time*.3,u_Time*.3) + (uv * 20.)) ;
    cl -= min(cl, vec4(-.3, .0, -.5, 1.));
    cl -= .8*dot(uv,uv);
    
    

    
	vec4 overlaper = mix( texcolorMain, cl, texcolorMain.a );
	gl_FragColor = overlaper * overlaper.a + texcolorMain * (1.0 - overlaper.a);
    //Output to screen
}