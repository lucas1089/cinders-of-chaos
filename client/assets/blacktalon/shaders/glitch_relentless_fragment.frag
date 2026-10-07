uniform float u_Depth;
uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;
uniform float u_Time;

// Better random function for more chaotic results
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Glitch block function
float glitchBlock(vec2 pos, float blockFactor, float timeFactor) {
    vec2 blockPos = floor(pos * blockFactor) / blockFactor;
    return step(0.8, random(blockPos + floor(timeFactor)));
}

void main()
{
    // Get base texture
    gl_FragColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Apply outfit coloring as in original shader
    if(texcolor.r > 0.9) {
        gl_FragColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        gl_FragColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        gl_FragColor *= u_Color[3];
    }
    
    vec2 pos = v_TexCoord;
    
    // Extreme RGB shifting - greater offset with erratic movement
    float rgbShiftTime = mod(u_Time, 3600.0);
    float rgbShiftAmplitude = 0.04 + 0.06 * sin(rgbShiftTime * 0.5);
    
    // Create screen tear effect
    float tearLine = floor(pos.y * 20.0) / 20.0;
    float tearOffset = 0.0;
    
    // Random horizontal screen tearing
    if (random(vec2(tearLine, floor(rgbShiftTime * 3.0))) > 0.85) {
        tearOffset = (random(vec2(tearLine, floor(rgbShiftTime))) - 0.5) * 0.2;
        pos.x += tearOffset;
    }
    
    // Random vertical screen tearing
    if (random(vec2(floor(pos.x * 20.0) / 20.0, floor(rgbShiftTime * 2.0))) > 0.95) {
        pos.y += (random(vec2(pos.x, floor(rgbShiftTime * 0.5))) - 0.5) * 0.1;
    }
    
    // Extreme color channel splitting
    vec3 col;
    col.r = texture2D(u_Tex0, vec2(pos.x + rgbShiftAmplitude * sin(rgbShiftTime * 0.3), 
                                   pos.y + rgbShiftAmplitude * cos(rgbShiftTime * 0.2))).r;
    col.g = texture2D(u_Tex0, vec2(pos.x, 
                                   pos.y + rgbShiftAmplitude * sin(rgbShiftTime * 0.5))).g;
    col.b = texture2D(u_Tex0, vec2(pos.x - rgbShiftAmplitude * cos(rgbShiftTime * 0.4), 
                                   pos.y - rgbShiftAmplitude * sin(rgbShiftTime * 0.3))).b;
    
    // Chaotic distortion effects
    float c = 1.0;
    c += 8.0 * sin(rgbShiftTime * 5.0 + pos.y * 2000.0);
    c += 5.0 * sin(rgbShiftTime * 2.0 + pos.y * 1000.0);
    c += 25.0 * sin(rgbShiftTime * 15.0 + pos.y * 10000.0);
    c += 1.5 * cos(rgbShiftTime * 2.0 + pos.x * 2.0);
    
    // Pixelation glitch blocks
    float blockIntensity = 50.0 + 50.0 * sin(rgbShiftTime * 0.2);
    float blockFactor = 0.0;
    
    // Randomly create pixelated blocks
    if (glitchBlock(pos, 10.0, rgbShiftTime * 0.1) > 0.5) {
        float blockSize = random(floor(pos * blockIntensity) / blockIntensity + floor(rgbShiftTime * 0.2));
        blockFactor = step(0.75, blockSize);
    }
    
    if (blockFactor > 0.0) {
        // Create pixelated effect for blocks
        float blockSize = 10.0 + 40.0 * random(vec2(floor(rgbShiftTime * 0.3)));
        vec2 blockPos = floor(pos * blockSize) / blockSize;
        col = texture2D(u_Tex0, blockPos).rgb;
        
        // Add noise to pixelated blocks
        float noise = random(blockPos + vec2(rgbShiftTime * 0.01));
        col = mix(col, vec3(noise), 0.3);
    }
    
    // Apply random noise
    pos += rgbShiftTime;
    float r = random(pos.xy * 1.5);
    float g = random(pos.xy * 9.5);
    float b = random(pos.xy * 3.5);
    
    // Create static noise effect
    float staticNoise = step(0.92, random(vec2(floor(pos.y * 80.0) / 80.0, floor(rgbShiftTime * 30.0))));
    if (staticNoise > 0.0) {
        col = vec3(r, g, b) * 0.5;
    }
    
    // Digital corruption lines
    float scanline = sin(pos.y * 100.0 - rgbShiftTime * 10.0) * 0.5 + 0.5;
    scanline = pow(scanline, 10.0) * 0.2;
    col = mix(col, vec3(1.0), scanline);
    
    // Strobing/flickering effect
    float flicker = sin(rgbShiftTime * 20.0) * 0.5 + 0.5;
    flicker = step(0.95, flicker) * 0.2;
    
    // Combine all effects with color shifting
    gl_FragColor.rgb = col * r * c * 0.5 * (1.0 + flicker);
    
    // Random color inversions
    if (random(vec2(floor(rgbShiftTime * 0.3))) > 0.95) {
        gl_FragColor.rgb = 1.0 - gl_FragColor.rgb;
    }
    
    // Occasionally brighten or darken the image
    float brightShift = step(0.8, random(vec2(floor(rgbShiftTime * 0.2))));
    gl_FragColor.rgb = mix(gl_FragColor.rgb, gl_FragColor.rgb * 1.5, brightShift);
    
    // Apply occasional hue shift
    float hueShift = random(vec2(floor(rgbShiftTime * 0.15)));
    if (hueShift > 0.7) {
        gl_FragColor.rgb = gl_FragColor.gbr; // Rotate color channels
    } else if (hueShift > 0.4) {
        gl_FragColor.rgb = gl_FragColor.brg; // Rotate color channels differently
    }
    
    if(gl_FragColor.a < 0.01) discard;
} 