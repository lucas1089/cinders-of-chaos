uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Lightning parameters - enhanced for bigger lightning
float intensity = 2.0;        // Overall lightning intensity - increased
float arcCount = 8.0;         // Number of lightning arcs - increased
float arcWidth = 0.06;        // Width of lightning bolts - doubled
float flashRate = 1.8;        // Rate of lightning flashes
float noiseScale = 12.0;      // Scale of noise pattern

// Hash function for pseudo-random values
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Create electric arc between two points - enhanced for more visibility
float electricArc(vec2 p, vec2 start, vec2 end, float time, float thickness, float turbulence) {
    // Vector from start to end
    vec2 path = end - start;
    float pathLength = length(path);
    vec2 dir = path / pathLength;
    vec2 normal = vec2(-dir.y, dir.x);
    
    // Project point onto line to get distance along path (0-1)
    float proj = clamp(dot(p - start, dir) / pathLength, 0.0, 1.0);
    
    // Create lightning effect by adding noise to path
    float noiseTime = time * 10.0;
    float noise = 0.0;
    
    // Add multiple frequencies of noise for natural look
    for(float i = 1.0; i < 5.0; i++) { // More noise iterations
        float scale = pow(2.0, i);
        float weight = pow(0.5, i);
        noise += weight * sin(proj * pathLength * scale * 0.5 + noiseTime * i);
    }
    
    // Calculate distance from path with increased width
    float dist = abs(dot(p - start, normal) - noise * turbulence * (proj * (1.0 - proj) * 4.0));
    
    // Create core and glow of lightning with wider reach
    float core = smoothstep(thickness, 0.0, dist);
    float glow = smoothstep(thickness * 4.0, 0.0, dist) * 0.7; // Wider glow
    
    // Add flicker effect
    float flicker = 0.8 + 0.2 * sin(time * 20.0 + proj * 5.0);
    
    // Combine core and glow with falloff at ends
    float falloff = sin(proj * 3.14159) * flicker;
    
    return (core + glow) * falloff;
}

// Generate multiple electric arcs with branching
float generateLightning(vec2 p, float time) {
    float result = 0.0;
    
    // Base time for lightning pattern
    float baseTime = time * flashRate;
    
    // Create several flashes of varying timing
    float flash = 0.0;
    flash += pow(sin(baseTime) * 0.5 + 0.5, 16.0) * 3.0; // Less steep curve
    flash += pow(sin(baseTime * 1.3) * 0.5 + 0.5, 8.0) * 2.0; // Less steep curve
    flash += pow(sin(baseTime * 0.7) * 0.5 + 0.5, 12.0) * 2.5; // Less steep curve
    flash = min(1.0, flash * 0.3); // Increased overall flash visibility
    
    // Always have a minimum flash level for visibility
    flash = max(flash, 0.15);
    
    // Generate multiple arcs
    for(float i = 0.0; i < arcCount; i++) {
        // Create semi-random start and end points
        float arcTime = baseTime + i * 1.234;
        float seed = i * 0.1 + floor(arcTime * 0.5);
        
        float angle1 = hash(vec2(seed, seed + 0.1)) * 6.283;
        float angle2 = hash(vec2(seed + 0.2, seed + 0.3)) * 6.283;
        
        // Adjust arc angles to create a more connected network
        if(i > 0.0) {
            angle1 = angle2 + 3.14159 * (hash(vec2(seed + 0.4, seed + 0.5)) - 0.5);
        }
        
        // Calculate arc start and end points - more centered for visibility
        float rad1 = hash(vec2(seed + 0.6, seed + 0.7)) * 0.4 + 0.1; // More centered
        float rad2 = hash(vec2(seed + 0.8, seed + 0.9)) * 0.4 + 0.1; // More centered
        
        vec2 start = vec2(cos(angle1), sin(angle1)) * rad1;
        vec2 end = vec2(cos(angle2), sin(angle2)) * rad2;
        
        // Calculate turbulence based on flash intensity - more intensity for visibility
        float turbulence = 0.3 + hash(vec2(seed + 1.0, seed + 1.1)) * 0.4;
        
        // Add arc with flicker effect
        float flicker = 0.7 + 0.3 * sin(arcTime * 20.0 + i);
        result += electricArc(p, start, end, arcTime, arcWidth, turbulence) * flicker * flash;
        
        // Add branches to main arcs
        if (i < 4.0) { // Only add branches to first few arcs
            // Calculate branch point position
            float branchPoint = hash(vec2(seed + 1.2, seed + 1.3)) * 0.6 + 0.2;
            vec2 branchStart = start + (end - start) * branchPoint;
            
            // Calculate branch angle - off from main arc
            float branchAngle = atan(end.y - start.y, end.x - start.x) + 
                              (hash(vec2(seed + 1.4, seed + 1.5)) - 0.5) * 1.5;
            
            // Calculate branch length
            float branchLength = hash(vec2(seed + 1.6, seed + 1.7)) * 0.2 + 0.1;
            
            // Calculate branch end point
            vec2 branchEnd = branchStart + vec2(cos(branchAngle), sin(branchAngle)) * branchLength;
            
            // Add the branch - slightly thinner
            float branchTurbulence = turbulence * 1.2; // More turbulent branches
            result += electricArc(p, branchStart, branchEnd, arcTime + 100.0, arcWidth * 0.8, branchTurbulence) * flicker * flash * 0.8;
        }
    }
    
    // Add ambient electricity - faint arcs in the background
    for(float i = 0.0; i < 3.0; i++) {
        float ambientSeed = i * 0.5 + floor(baseTime * 0.2);
        float ambAngle1 = hash(vec2(ambientSeed, ambientSeed + 0.1)) * 6.283;
        float ambAngle2 = ambAngle1 + (hash(vec2(ambientSeed + 0.2, ambientSeed + 0.3)) - 0.5) * 3.0;
        
        float ambRad1 = hash(vec2(ambientSeed + 0.4, ambientSeed + 0.5)) * 0.8 + 0.2;
        float ambRad2 = hash(vec2(ambientSeed + 0.6, ambientSeed + 0.7)) * 0.8 + 0.2;
        
        vec2 ambStart = vec2(cos(ambAngle1), sin(ambAngle1)) * ambRad1;
        vec2 ambEnd = vec2(cos(ambAngle2), sin(ambAngle2)) * ambRad2;
        
        float ambTurbulence = 0.1 + hash(vec2(ambientSeed + 0.8, ambientSeed + 0.9)) * 0.1;
        float ambFlicker = 0.5 + 0.5 * sin(baseTime * 5.0 + i * 10.0);
        
        // Add faint background arcs
        result += electricArc(p, ambStart, ambEnd, baseTime + 200.0, arcWidth * 1.5, ambTurbulence) * ambFlicker * 0.4;
    }
    
    return min(1.0, result * intensity);
}

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
    
    // Get distance and angle from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float angle = v_TexCoord3.y;
    
    // Create coordinates for lightning effect
    vec2 coord = vec2(cos(angle), sin(angle)) * distFromCenter;
    
    // Generate lightning
    float time = u_Time;
    float lightning = generateLightning(coord, time);
    
    // Create electric color - brighter for visibility
    vec3 electricColor = vec3(0.7, 0.9, 1.0); // Brighter blue-white
    
    // Add color variation based on angle and distance
    float colorVar = sin(angle * 3.0 + time * 0.5) * 0.5 + 0.5;
    electricColor = mix(
        electricColor, 
        mix(vec3(0.6, 0.8, 1.0), vec3(0.9, 0.9, 1.0), colorVar), 
        colorVar
    );
    
    // Add constant ambient electricity
    float ambientElectricity = (1.0 - distFromCenter) * 0.4;
    
    // Add ambient glow - brighter center
    float ambientGlow = pow(1.0 - distFromCenter, 2.0) * 0.5; // Increased
    
    // Create flash effect
    float flash = pow(sin(time * flashRate) * 0.5 + 0.5, 16.0) * 3.0;
    flash += pow(sin(time * flashRate * 1.3) * 0.5 + 0.5, 8.0) * 2.0;
    flash = min(1.0, flash * 0.3);
    
    // Add glow during flashes
    float totalGlow = ambientGlow + flash * 0.7 + ambientElectricity;
    
    // Combine lightning and ambient effect
    vec3 finalEffect = electricColor * (lightning + totalGlow);
    
    // Add subtle electric haze over the entire character
    finalEffect += electricColor * 0.15 * (1.0 - distFromCenter);
    
    // Create edge highlight - full circle of electricity
    float edge = smoothstep(0.7, 1.0, distFromCenter) * 0.8;
    finalEffect += electricColor * edge * (sin(time * 5.0 + angle * 5.0) * 0.4 + 0.6);
    
    // Mix with original texture
    float effectStrength = 0.9 - distFromCenter * 0.2; // Less falloff at edges
    baseColor.rgb = mix(baseColor.rgb, baseColor.rgb * 0.1 + finalEffect, effectStrength);
    
    // Add extra brightness to the lightning
    baseColor.rgb += lightning * electricColor * 0.5;
    
    // Set output color
    gl_FragColor = baseColor;
} 