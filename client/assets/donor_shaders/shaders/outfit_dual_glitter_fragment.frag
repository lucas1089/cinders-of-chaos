uniform mat4 u_Color;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform float u_Time;

varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
varying vec4 v_Color;

// Blending parameters
float blendSpeed = 0.3;     // Speed of the blend oscillation
float noiseAmount = 0.15;   // Amount of noise to add
float hueShiftSpeed = 0.2;  // Speed of hue shifting

// Glitter parameters
float glitterDensity = 30.0;  // Higher = more glitter particles
float glitterSpeed = 5.0;     // Speed of glitter animation
float glitterSize = 0.8;      // Size of glitter particles (lower = larger)
float glitterBrightness = 0.6; // Brightness of glitter effect

// RGB to HSV conversion function
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB conversion function
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Apply hue shift to a color
vec3 shiftHue(vec3 color, float shift) {
    vec3 hsv = rgb2hsv(color);
    hsv.x = fract(hsv.x + shift); // Shift hue only
    return hsv2rgb(hsv);
}

// Pseudo-random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Function to generate glitter effect
float glitter(vec2 uv, float time) {
    // Create cells for glitter placement
    vec2 cell = floor(uv * glitterDensity);
    vec2 cellUv = fract(uv * glitterDensity);
    
    // Each cell gets its own random value
    float cellRandom = random(cell);
    
    // Animate the glitter with time
    float t = fract(cellRandom + time * glitterSpeed * 0.1);
    
    // Glitter appears and disappears
    float glitterAppear = smoothstep(0.9, 1.0, t) * (1.0 - smoothstep(0.0, 0.1, t)) * 10.0;
    
    // Make glitter particle position random within cell
    vec2 glitterPos = vec2(
        random(cell + 0.1),
        random(cell + 0.2)
    );
    
    // Calculate distance to glitter particle position
    float dist = distance(cellUv, glitterPos);
    
    // Create the glitter point with soft edge
    float glitterPoint = 1.0 - smoothstep(0.0, glitterSize * 0.1, dist);
    
    return glitterPoint * glitterAppear * glitterBrightness;
}

void main()
{
    // Sample the original texture
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample both trippy textures
    vec4 texture1 = texture2D(u_Tex1, v_TexCoord3);
    vec4 texture2 = texture2D(u_Tex2, v_TexCoord4);
    
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
        // Create oscillating blend with limited range
        float blendAmount = sin(u_Time * blendSpeed) * 0.4 + 0.5;
        
        // Add some noise to the blend for more interesting patterns
        float noiseValue = random(v_TexCoord3 * 10.0 + u_Time * 0.1) * noiseAmount;
        blendAmount = clamp(blendAmount + noiseValue, 0.2, 0.8);
        
        // Blend the two textures
        vec3 blendedTexture = mix(texture1.rgb, texture2.rgb, blendAmount);
        
        // Apply subtle hue shift
        float hueShift = sin(u_Time * hueShiftSpeed) * 0.1;
        blendedTexture = shiftHue(blendedTexture, hueShift);
        
        // Generate glitter effect
        float glitterEffect = glitter(v_TexCoord, u_Time);
        
        // Extract color from texture for glitter
        vec3 glitterColor = max(texture1.rgb, texture2.rgb);
        
        // Mix base color, blended texture and add glitter
        vec3 finalColor = mix(baseColor.rgb, blendedTexture, 0.75);
        finalColor += glitterColor * glitterEffect;
        
        // Ensure we don't exceed the maximum brightness
        finalColor = min(finalColor, vec3(1.0));
        
        gl_FragColor = vec4(finalColor, baseColor.a);
    }
    
    // Discard transparent pixels
    if(gl_FragColor.a < 0.01) discard;
} 