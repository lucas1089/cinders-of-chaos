uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Glitch parameters
float glitchSpeed = 0.8; // Speed of glitching
float glitchAmount = 0.02; // Amount of glitch distortion
float rgbShiftAmount = 0.004; // Amount of RGB shifting
float noiseAmount = 0.1; // Amount of noise static

// Simple hash function for noise
float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

// Noise function
float noise(vec2 p) {
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    fp = fp * fp * (3.0 - 2.0 * fp);
    
    float n = ip.x + ip.y * 57.0;
    float a = hash(n);
    float b = hash(n + 1.0);
    float c = hash(n + 57.0);
    float d = hash(n + 58.0);
    
    return mix(mix(a, b, fp.x), mix(c, d, fp.x), fp.y);
}

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Calculate time for glitch effect
    float time = u_Time * glitchSpeed;
    
    // Create random glitch sections based on y coordinate
    float blockOffset = 0.0;
    if (fract(v_TexCoord.y * 10.0 + time) < 0.3) {
        blockOffset = hash(floor(v_TexCoord.y * 10.0) + time) * glitchAmount;
        // Sometimes move blocks left, sometimes right
        blockOffset *= sign(hash(floor(v_TexCoord.y * 10.0) + time * 1.5) - 0.5) * 2.0;
    }
    
    // Create occasional vertical glitch jumps
    float verticalJump = 0.0;
    if (hash(time * 5.0) < 0.1) {
        verticalJump = hash(floor(v_TexCoord.x * 10.0) + time) * glitchAmount * 0.5;
    }
    
    // Apply glitch to texture coordinates
    vec2 glitchCoord = v_TexCoord;
    glitchCoord.x += blockOffset;
    glitchCoord.y += verticalJump;
    
    // Apply RGB shifting
    float rgbShift = sin(time * 10.0) * rgbShiftAmount;
    vec4 rColor = texture2D(u_Tex0, vec2(glitchCoord.x + rgbShift, glitchCoord.y));
    vec4 gColor = texture2D(u_Tex0, glitchCoord);
    vec4 bColor = texture2D(u_Tex0, vec2(glitchCoord.x - rgbShift, glitchCoord.y));
    
    // Create glitched color
    vec4 baseColor = vec4(rColor.r, gColor.g, bColor.b, gColor.a);
    
    // If distortion led to transparent pixel, use original
    if (baseColor.a < 0.01) {
        baseColor = originalColor;
    }
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Add static noise
    float staticNoise = noise(vec2(glitchCoord.x * 100.0 + time * 10.0, glitchCoord.y * 100.0));
    baseColor.rgb = mix(baseColor.rgb, vec3(staticNoise), noiseAmount * hash(time * 0.1));
    
    // Add occasional scan lines
    if (fract(v_TexCoord.y * 30.0 + time) < 0.1) {
        baseColor.rgb *= 0.8;
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 