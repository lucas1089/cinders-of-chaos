uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Electric Southeast parameters
float electricLineWidth = 0.15; // Wider electric lines for more spacing
float electricIntensity = 0.7; // Intensity of electric effect
float darkCloudIntensity = 0.4; // Intensity of dark cloud effect
float secondaryLineFreq = 7.0; // Lower frequency for secondary lines (more space)

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
    float burstIntensity = v_TexCoord3.y; // Dark cloud burst intensity
    
    // Create primary electric diagonal lines - spaced farther apart
    float diagonalPattern = fract(diagonal * 3.0 - u_Time * 2.0);
    float electricLine = smoothstep(1.0 - electricLineWidth, 1.0, diagonalPattern) + 
                        smoothstep(0.0, electricLineWidth, diagonalPattern);
    
    // Create secondary curved electric lines - even more spaced
    float secondaryDiagonal = sin(diagonal * secondaryLineFreq + u_Time * 2.5) * 0.5 + 0.5;
    float secondaryLine = smoothstep(0.7, 0.8, secondaryDiagonal);
    
    // Combine electric lines
    float combinedLines = max(electricLine * 0.8, secondaryLine * 0.3);
    
    // Apply purplish blue electric color
    vec3 electricColor = vec3(0.3, 0.4, 1.0); // Purplish blue
    
    // Create dark cloud effect that pulses
    vec3 darkCloudColor = vec3(0.1, 0.05, 0.3); // Very dark purple/blue
    
    // Mix in dark cloud during pulse bursts
    vec3 finalElectricColor = mix(electricColor, darkCloudColor, burstIntensity * 0.7);
    
    // Apply subtle background cloud effect
    baseColor.rgb = mix(baseColor.rgb, darkCloudColor, burstIntensity * darkCloudIntensity * 0.5);
    
    // Apply electric lines with intensity
    baseColor.rgb += finalElectricColor * combinedLines * electricIntensity;
    
    // During dark cloud bursts, add a subtle glow to the whole character
    baseColor.rgb = mix(baseColor.rgb, finalElectricColor * 0.5, burstIntensity * 0.2);
    
    // Apply pulsating white flashes during peak bursts
    if(burstIntensity > 0.7 && combinedLines > 0.3) {
        // Add white glow along the electric lines during bursts
        float flashIntensity = (burstIntensity - 0.7) * 3.33; // 0 to 1 during peak
        baseColor.rgb += vec3(1.0) * combinedLines * flashIntensity * 0.5;
    }
    
    // Create rain-like falling effect more visible during bursts
    float rainPattern = fract(v_TexCoord.y * 5.0 - u_Time * 3.0);
    rainPattern = smoothstep(0.9, 1.0, rainPattern);
    baseColor.rgb += electricColor * rainPattern * burstIntensity * 0.2;
    
    // Set output color
    gl_FragColor = baseColor;
} 