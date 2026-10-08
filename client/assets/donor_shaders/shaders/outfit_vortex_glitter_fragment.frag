uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Vortex Glitter parameters
float vortexSpeed = 0.8;          // Speed of vortex rotation
float vortexTightness = 4.0;      // How tight the vortex spiral is
float vortexIntensity = 0.35;     // Overall intensity of the vortex effect
float glitterAmount = 0.5;        // Amount of glitter particles
float glitterSpeed = 2.0;         // Speed of glitter animation
float upwardSpeed = 1.2;          // Speed of upward movement

// Hash function for random noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
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
    
    // Get normalized coordinates (0-1 range, centered at 0.5, 0.5)
    vec2 centeredCoord = v_TexCoord - vec2(0.5, 0.5);
    
    // Calculate distance from center and angle for vortex effect
    float dist = length(centeredCoord);
    float angle = atan(centeredCoord.y, centeredCoord.x);
    
    // Get vertex distortion info
    float distFromCenter = v_TexCoord3.x; 
    float angleFromCenter = v_TexCoord3.y;
    
    // Create vortex spiral effect
    // Rotate coordinates around center based on distance and time
    float vortexAngle = angle + dist * vortexTightness + u_Time * vortexSpeed;
    
    // Create distortion for primary texture coordinates
    vec2 vortexOffset = vec2(
        cos(vortexAngle) * dist * vortexIntensity,
        sin(vortexAngle) * dist * vortexIntensity
    );
    
    // Create upward flowing motion
    float upwardOffset = fract(u_Time * upwardSpeed + dist * 2.0);
    
    // Add upward movement to vortex offset
    vortexOffset.y -= upwardOffset * 0.1;
    
    // Apply vortex distortion to texture coordinates
    vec2 distortedCoord = v_TexCoord + vortexOffset;
    
    // Sample distorted texture
    vec4 distortedColor = texture2D(u_Tex0, distortedCoord);
    
    // Add glitter effect
    float glitterPattern = 0.0;
    
    // Create multiple layers of glitter particles
    for (int i = 0; i < 3; i++) {
        // Create grid for glitter positioning
        float scale = 10.0 + float(i) * 5.0;
        vec2 glitterCoord = v_TexCoord * scale;
        
        // Add vortex motion to glitter
        glitterCoord += vec2(
            cos(angle + u_Time * (0.5 + float(i) * 0.2)) * dist * 5.0,
            sin(angle + u_Time * (0.5 + float(i) * 0.2)) * dist * 5.0
        );
        
        // Add upward motion
        glitterCoord.y -= u_Time * glitterSpeed * (1.0 + float(i) * 0.3);
        
        // Calculate glitter cell ID
        vec2 glitterCell = floor(glitterCoord);
        
        // Generate random values for each cell
        float cellRandom = hash(glitterCell);
        float cellRandom2 = hash(glitterCell + vec2(43.12, 17.35));
        
        // Only create glitter in some cells
        if (cellRandom > 0.7) {
            // Calculate position within cell
            vec2 cellPosition = fract(glitterCoord);
            
            // Random position within the cell
            vec2 glitterPos = vec2(
                cellRandom2 * 0.8 + 0.1,
                fract(cellRandom * 8.371) * 0.8 + 0.1
            );
            
            // Calculate distance to glitter position
            float glitterDist = length(cellPosition - glitterPos);
            
            // Create glitter particle with pulsating size
            float glitterSize = 0.2 - 0.1 * float(i);
            float pulseSize = glitterSize * (0.8 + 0.2 * sin(u_Time * 3.0 + cellRandom * 6.28));
            
            // Add glitter contribution (brighter for closer particles)
            glitterPattern += smoothstep(pulseSize, 0.0, glitterDist) * (1.0 - 0.2 * float(i));
        }
    }
    
    // Create vortex-based color shifts
    vec3 vortexColor1 = vec3(0.9, 0.5, 0.2); // Orange
    vec3 vortexColor2 = vec3(0.2, 0.4, 0.9); // Blue
    
    // Blend vortex colors based on angle and time
    float colorBlend = 0.5 + 0.5 * sin(angle * 2.0 + u_Time);
    vec3 vortexColor = mix(vortexColor1, vortexColor2, colorBlend);
    
    // Add glitter with vortex color
    vec3 glitterColor = mix(vortexColor, vec3(1.0), 0.5) * glitterPattern * glitterAmount;
    
    // Mix base color with distorted color
    vec3 finalColor = mix(baseColor.rgb, distortedColor.rgb, vortexIntensity + dist * 0.3);
    
    // Add glitter
    finalColor += glitterColor;
    
    // Set output color
    gl_FragColor = vec4(finalColor, baseColor.a);
} 