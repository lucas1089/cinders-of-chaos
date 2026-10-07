uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Electric Eel parameters
float electricLineWidth = 0.08; // Width of electric lines (reduced from 0.1)
float electricIntensity = 0.5; // Intensity of electric effect (reduced from 0.7)
float burstIntensity = 0.6; // Intensity of white light bursts (reduced from 1.0)
float secondaryLineFreq = 10.0; // Frequency of secondary electric lines (reduced from 12.0)

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
    
    // Extract data from vertex shader
    float diagonal = v_TexCoord3.x; // Diagonal position value
    float burst = v_TexCoord3.y; // Burst intensity
    
    // Create primary electric diagonal lines
    float diagonalPattern = fract(diagonal * 4.0 - u_Time * 2.0);
    float electricLine = smoothstep(1.0 - electricLineWidth, 1.0, diagonalPattern) + 
                        smoothstep(0.0, electricLineWidth, diagonalPattern);
    
    // Create secondary curved electric lines
    float secondaryDiagonal = sin(diagonal * secondaryLineFreq + u_Time * 3.0) * 0.5 + 0.5;
    float secondaryLine = smoothstep(0.6, 0.7, secondaryDiagonal);
    
    // Combine electric lines
    float combinedLines = max(electricLine * 0.7, secondaryLine * 0.4);
    
    // Apply purplish blue electric color
    vec3 electricColor = vec3(0.3, 0.4, 1.0); // Purplish blue
    
    // Pulse the electricty color for more effect - reduced speed and intensity
    float pulse = sin(u_Time * 3.0) * 0.4 + 0.5; // Reduced from 5.0 speed and 0.5 amplitude
    electricColor = mix(electricColor, vec3(0.5, 0.0, 1.0), pulse * 0.4); // Reduced from 0.5 mix
    
    // Apply subtle background glow - reduced intensity
    baseColor.rgb = mix(baseColor.rgb, electricColor * 0.4, 0.15); // Reduced from 0.5, 0.2
    
    // Apply electric lines with intensity
    baseColor.rgb += electricColor * combinedLines * electricIntensity;
    
    // Apply white light bursts during burst peaks
    if(burst > 0.1) {
        // White flashing during bursts
        float flashIntensity = burst * burstIntensity;
        
        // Make the white flash centered on the electric lines
        float burstMask = smoothstep(0.2, 0.8, combinedLines) * flashIntensity;
        
        // Apply white burst light
        baseColor.rgb += vec3(1.0) * burstMask;
        
        // Add extra sparkle effect during bursts
        float sparkle = fract(sin(v_TexCoord.x * 100.0 + v_TexCoord.y * 100.0 + u_Time * 10.0) * 43758.5453);
        if(sparkle > 0.97 && combinedLines > 0.5) {
            baseColor.rgb = vec3(1.0); // Pure white sparkles
        }
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 