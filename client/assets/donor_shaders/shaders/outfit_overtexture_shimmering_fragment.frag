uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_Position;
varying float v_Intensity;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

// Bouncing balls parameters
const int NUM_BALLS = 3;
varying vec2 v_BallPositions[NUM_BALLS];
varying float v_BallSizes[NUM_BALLS];

// Shimmering CONFIG
float shimmerSpeed = 5.0;
float shimmerHeight = 12.0;
float shimmerAngle = 50.0; // degrees
float shimmerIntensity = 1.5;

vec2 rotate(vec2 v, float a) {
    float s = sin(a);
    float c = cos(a);
    mat2 m = mat2(c, -s, s, c);
    return m * v;
}

void main()
{
    // Sample the base texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 effectColor = texture2D(u_Tex1, v_TexCoord3);
    
    // Apply color based on outfit parts (from shimmering shader)
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }

    // Initialize our result with the base color
    gl_FragColor = baseColor;
    
    // Calculate bouncing balls effect (from velvet)
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
    
    if(texcolor.a > 0.9) {
        // Apply velvet effect
        float glowIntensity = 2.0 + sin(u_Time * 2.0) * 0.5;
        vec3 enhancedColor = effectColor.rgb * glowIntensity * v_Intensity;
        
        // Add some color variation
        float hueShift = sin(u_Time * 0.5) * 0.1;
        enhancedColor.r += hueShift;
        enhancedColor.g += hueShift * 0.5;
        
        // Apply shimmering effect (from shimmering shader)
        vec2 p = rotate(v_Position, (shimmerAngle / 180.0) * 3.14);
        float frame = mod(p.y, shimmerHeight);
        float timeFrame = mod(u_Time * shimmerSpeed, shimmerHeight);
        float dist = min(abs(frame - timeFrame), min(abs(frame - timeFrame - shimmerHeight), abs(frame - timeFrame + shimmerHeight)));
        float shimmerFactor = shimmerIntensity / sqrt(max(1.0, dist));
        
        // Combine velvet and shimmering effects
        gl_FragColor.rgb = baseColor.rgb * (enhancedColor + ballColor) * shimmerFactor;
        
        // Add a subtle rim light effect
        float rim = 1.0 - abs(dot(normalize(vec3(v_TexCoord - 0.5, 0.0)), vec3(0.0, 0.0, 1.0)));
        rim = pow(rim, 3.0);
        gl_FragColor.rgb += rim * 0.3 * enhancedColor;
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 