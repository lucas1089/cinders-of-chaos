uniform mat4 u_Color;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;

varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec4 v_Color;
varying vec2 v_Position;

// TV static noise effect parameters
float noiseIntensity = 0.25; // Intensity of the static noise
float noiseScale = 100.0;   // Scale of the noise pattern
float colorfulnessAmount = 0.8; // How colorful the noise is
float textureWeight = 0.7;  // Weight of the texture vs noise

// Pseudo-random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// More complex noise function
float noise(vec2 st, float time) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    
    // Four corners in 2D of a tile
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    
    // Cubic Hermine curve
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    // Mix 4 corners percentages
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Color noise function that changes over time
vec3 colorNoise(vec2 uv, float time) {
    float r = noise(uv * 1.1 + time * 0.3, time);
    float g = noise(uv * 1.2 + time * 0.5, time);
    float b = noise(uv * 1.3 + time * 0.7, time);
    return vec3(r, g, b);
}

void main()
{
    // Sample the original texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 overlayTexture = texture2D(u_Tex1, v_TexCoord3);
    
    // Apply outfit colors based on the texture channels
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Set initial output color
    gl_FragColor = baseColor;
    
    if(texcolor.a > 0.9) {
        // Generate TV static noise
        vec2 noiseCoord = v_Position * noiseScale;
        float staticNoise = random(noiseCoord + u_Time * 100.0);
        
        // Make the noise colorful
        vec3 coloredNoise = colorNoise(noiseCoord, u_Time);
        
        // Sample a random pixel from the overlay texture to color the noise
        vec2 randomOffset = vec2(
            sin(u_Time * 2.3 + v_Position.y * 10.0) * 0.1,
            cos(u_Time * 2.1 + v_Position.x * 10.0) * 0.1
        );
        vec4 randomPixel = texture2D(u_Tex1, fract(v_TexCoord3 + randomOffset));
        
        // Mix the texture and noise based on the texture's brightness
        float textureBrightness = (overlayTexture.r + overlayTexture.g + overlayTexture.b) / 3.0;
        textureBrightness = pow(textureBrightness, 0.5); // Adjust gamma for better visibility
        
        // Apply the colorful static effect
        vec3 staticEffect = mix(
            coloredNoise * staticNoise,
            randomPixel.rgb * coloredNoise,
            colorfulnessAmount
        );
        
        // Combine base color with static effect
        vec3 finalColor = mix(
            baseColor.rgb,
            overlayTexture.rgb + staticEffect * noiseIntensity,
            textureWeight
        );
        
        // Brighten the result to ensure it's vibrant
        finalColor = min(finalColor * 1.3, vec3(1.0));
        
        gl_FragColor = vec4(finalColor, baseColor.a);
    }
    
    // Discard transparent pixels
    if(gl_FragColor.a < 0.01) discard;
} 