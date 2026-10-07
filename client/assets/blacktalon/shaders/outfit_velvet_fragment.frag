uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying float v_Intensity;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Bouncing balls parameters
const int NUM_BALLS = 3;
varying vec2 v_BallPositions[NUM_BALLS];
varying float v_BallSizes[NUM_BALLS];

void main()
{
    // Sample the base texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 effectColor = texture2D(u_Tex1, v_TexCoord3);
    
    // Create a dynamic color shift
    float hueShift = sin(u_Time * 0.5) * 0.1;
    vec3 rgb = effectColor.rgb;
    float maxChannel = max(max(rgb.r, rgb.g), rgb.b);
    float minChannel = min(min(rgb.r, rgb.g), rgb.b);
    float delta = maxChannel - minChannel;
    
    // Calculate bouncing balls effect
    vec3 ballColor = vec3(0.0);
    for(int i = 0; i < NUM_BALLS; i++) {
        float dist = length(v_TexCoord - v_BallPositions[i]);
        float ballSize = v_BallSizes[i];
        
        // Create a pixelated ball effect
        vec2 pixelCoord = floor(v_TexCoord * 100.0) / 100.0;
        vec2 ballPixelCoord = floor(v_BallPositions[i] * 100.0) / 100.0;
        float pixelDist = length(pixelCoord - ballPixelCoord);
        
        if(pixelDist < ballSize) {
            // Create a glowing effect for the balls
            float glow = 1.0 - smoothstep(0.0, ballSize, pixelDist);
            vec3 ballGlow = vec3(1.0, 0.8, 0.6) * glow * (1.0 + sin(u_Time * 3.0 + float(i) * 2.0) * 0.3);
            ballColor += ballGlow;
        }
    }
    
    // Apply color enhancement
    if(texcolor.a > 0.9) {
        // Create a more dynamic effect
        float glowIntensity = 2.0 + sin(u_Time * 2.0) * 0.5;
        vec3 enhancedColor = effectColor.rgb * glowIntensity * v_Intensity;
        
        // Add some color variation
        enhancedColor.r += hueShift;
        enhancedColor.g += hueShift * 0.5;
        
        // Apply the enhanced effect and add the balls
        gl_FragColor = baseColor * vec4(enhancedColor + ballColor, effectColor.a);
        
        // Add a subtle rim light effect
        float rim = 1.0 - abs(dot(normalize(vec3(v_TexCoord - 0.5, 0.0)), vec3(0.0, 0.0, 1.0)));
        rim = pow(rim, 3.0);
        gl_FragColor.rgb += rim * 0.3 * enhancedColor;
    } else {
        gl_FragColor = baseColor;
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 