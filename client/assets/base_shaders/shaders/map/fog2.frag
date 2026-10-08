uniform float u_Time;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
varying vec2 v_TexCoord;

// Amount of detail.
int octaves=2;

// Opacity of the output fog.
float starting_amplitude=0.5;// :hint_range(0.,.5)=.5;

// Rate of pattern within the fog.
float starting_frequency=1.;

// Shift towards transparency (clamped) for sparser fog.
float shift=-.2;// :hint_range(-1.,0.)=-.2;

// Direction and speed of travel.
vec2 velocity=vec2(.1,.1);

// Color of the fog.
vec4 fog_color=vec4(0.9451, 0.9255, 0.5333, 0.988);// :hint_color=vec4(0.,0.,0.,1.);

// Noise texture; OpenSimplexNoise is great, but any filtered texture is fine.
// sampler2D noise;

float rand(vec2 uv){
    float amplitude=starting_amplitude;
    float frequency=starting_frequency;
    float outputs=0.;
    for(int i=0;i<octaves;i++){
        outputs+=texture2D(u_Tex1,uv*frequency).x*amplitude;
        amplitude/=2.;
        frequency*=2.;
    }
    return clamp(outputs+shift,0.,1.);
}

void main(void)
{
    gl_FragColor=texture2D(u_Tex0,v_TexCoord);
    vec2 motion=vec2(rand(v_TexCoord+u_Time*starting_frequency*velocity));
    vec4 fog=mix(gl_FragColor,fog_color,rand(v_TexCoord+motion));
    gl_FragColor=fog;
}
