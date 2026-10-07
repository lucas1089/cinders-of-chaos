uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Wave fragment parameters
float colorWaveSpeed = 1.8; // Speed of color waves
float colorWaveIntensity = 0.1; // Intensity of color waves
float colorShiftAmount = 0.05; // Amount of color shifting

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample texture with normal coordinates
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Add flowing color waves
    float time = u_Time * colorWaveSpeed;
    
    // Create a flowing wave pattern based on texture coords
    float colorWave = sin(v_TexCoord.y * 10.0 + time) * 0.5 + 0.5;
    colorWave *= sin(v_TexCoord.x * 8.0 - time * 0.7) * 0.5 + 0.5;
    
    // Add subtle color shifting
    vec3 colorShift;
    colorShift.r = sin(time * 0.5) * colorShiftAmount;
    colorShift.g = sin(time * 0.6 + 2.0) * colorShiftAmount;
    colorShift.b = sin(time * 0.7 + 4.0) * colorShiftAmount;
    
    // Apply color wave and shift
    baseColor.rgb += colorWave * colorWaveIntensity;
    baseColor.rgb += colorShift;
    
    // Set output color
    gl_FragColor = baseColor;
} 