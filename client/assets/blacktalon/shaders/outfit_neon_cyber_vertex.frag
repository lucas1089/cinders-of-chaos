attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform float u_Time;

// Neon cyber parameters
float circuitSpeed = 1.2; // Speed of circuit pulse movement
float circuitFrequency = 15.0; // Frequency of neon circuit lines
float glitchAmount = 0.004; // Amount of glitch distortion

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create glitch effect for horizontal lines
    // Create different glitch zones that shift over time
    float glitchZone = step(0.8, fract(normalizedPos.y * 7.0 + u_Time * 0.3));
    
    // Generate glitch offset
    vec2 glitchOffset = vec2(0.0);
    if(glitchZone > 0.0) {
        // Apply horizontal glitchy offset
        glitchOffset.x = sin(u_Time * 5.0 + normalizedPos.y * 20.0) * glitchAmount;
    }
    
    // Add cyber circuit pattern displacement
    float circuitPattern = sin(normalizedPos.x * circuitFrequency + u_Time * circuitSpeed) * 
                          sin(normalizedPos.y * circuitFrequency + u_Time * circuitSpeed);
    circuitPattern = smoothstep(0.8, 1.0, abs(circuitPattern));
    
    // Apply subtle circuit pattern movement
    vec2 circuitOffset = normalize(normalizedPos) * circuitPattern * 0.003;
    
    // Calculate final position with offset
    vec2 finalPos = origPosition.xy + glitchOffset + circuitOffset;
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position, glitch zone, and circuit pattern to fragment shader
    v_TexCoord3 = vec3(normalizedPos.x, normalizedPos.y, u_Time).xy;
} 