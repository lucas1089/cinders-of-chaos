uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Neon cyber parameters
float neonIntensity = 0.6; // Intensity of neon glow
float circuitIntensity = 0.45; // Intensity of circuit lines
float pulseBrightness = 0.3; // Pulse brightness variation
vec3 neonPurple = vec3(0.6, 0.0, 1.0); // Neon purple color
vec3 neonCyan = vec3(0.0, 0.8, 1.0); // Neon cyan color
vec3 neonBlue = vec3(0.0, 0.4, 1.0); // Neon blue color

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
    
    // Apply outfit colors, but more subtly to allow neon to show
    if(texcolor.r > 0.9) {
        baseColor *= mix(vec4(1.0), texcolor.g > 0.9 ? u_Color[0] : u_Color[1], 0.7);
    } else if(texcolor.g > 0.9) {
        baseColor *= mix(vec4(1.0), u_Color[2], 0.7);
    } else if(texcolor.b > 0.9) {
        baseColor *= mix(vec4(1.0), u_Color[3], 0.7);
    }
    
    // Get normalized position and time from vertex shader
    vec2 normalizedPos = v_TexCoord3.xy;
    float time = u_Time;
    
    // Create pulsing brightness
    float pulse = sin(time * 1.2) * 0.5 + 0.5;
    
    // Darken the base a bit to make neon pop
    vec3 darkBase = baseColor.rgb * vec3(0.4, 0.3, 0.5);
    
    // Create horizontal neon lines (cyber grid)
    float horizLines = smoothstep(0.9, 1.0, abs(sin(normalizedPos.y * 15.0)));
    
    // Create vertical neon lines (cyber grid)
    float vertLines = smoothstep(0.9, 1.0, abs(sin(normalizedPos.x * 15.0)));
    
    // Create diagonal neon lines
    float diagLines = smoothstep(0.9, 1.0, abs(sin((normalizedPos.x + normalizedPos.y) * 10.0)));
    
    // Create circuit pattern
    float circuits = sin(normalizedPos.x * 20.0 + time * 0.8) * sin(normalizedPos.y * 20.0 + time);
    circuits = smoothstep(0.8, 1.0, abs(circuits));
    
    // Create moving circuit pulse
    float circuitPulse = sin(normalizedPos.x * 5.0 + normalizedPos.y * 5.0 - time * 2.0) * 0.5 + 0.5;
    circuitPulse = pow(circuitPulse, 4.0); // Make pulse sharper
    
    // Combine all line patterns
    float combinedLines = max(max(horizLines, vertLines), diagLines);
    
    // Add circuit pattern to lines
    float neonPattern = max(combinedLines, circuits * circuitIntensity);
    
    // Add pulse to circuits for moving light effect
    neonPattern = max(neonPattern, circuitPulse * 0.5);
    
    // Create color shift effect for neon
    float colorShift = sin(normalizedPos.x * 3.0 + time * 0.5) * 0.5 + 0.5;
    vec3 neonColor = mix(neonPurple, neonCyan, colorShift);
    neonColor = mix(neonColor, neonBlue, sin(time * 0.7) * 0.5 + 0.5);
    
    // Apply neon pattern with pulsing brightness
    vec3 withNeon = darkBase + neonColor * neonPattern * neonIntensity * (pulse * pulseBrightness + 0.7);
    
    // Add edge glow
    float edgeDist = 1.0 - length(normalizedPos);
    float edgeGlow = smoothstep(0.3, 0.7, edgeDist) * 0.3;
    withNeon += neonColor * edgeGlow;
    
    // Add bright flashes on line intersections
    float intersections = horizLines * vertLines;
    withNeon += vec3(1.0, 1.0, 1.0) * intersections * pulse;
    
    // Set output color
    gl_FragColor = vec4(withNeon, baseColor.a);
} 