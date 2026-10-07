uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;
uniform vec4 u_Color;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;
varying vec2 v_Position;

void main()
{
    // Get the texture color
    vec4 textureColor = texture2D(u_Tex0, v_TexCoord);
    
    // Create pulsing purple effect based on time
    float pulseIntensity = 0.7 + 0.3 * sin(u_Time * 2.0);
    
    // Purple color base (adjust these values for different purple shades)
    vec3 purpleColor = vec3(0.6, 0.1, 0.9) * pulseIntensity;
    
    // Apply purple glow only to opaque parts of the texture
    vec4 finalColor = vec4(textureColor.rgb * purpleColor, textureColor.a);
    
    // Apply UI element's color
    gl_FragColor = finalColor * u_Color;
} 