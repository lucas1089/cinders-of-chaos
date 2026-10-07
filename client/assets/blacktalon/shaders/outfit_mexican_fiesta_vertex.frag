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

// Mexican Fiesta parameters
float patternSpeed = 1.0; // Speed of pattern movement
float wavyAmount = 0.02; // Amount of wavy movement
float sombreroBounce = 0.03; // Amount of sombrero bounce

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create festive wavy movement - like a dance
    float wavyPhase = u_Time * patternSpeed;
    
    // Different wavy patterns for different parts of the sprite
    float wavyX = 0.0;
    float wavyY = 0.0;
    
    // Sombrero bounce on top of head
    if (normalizedPos.y < -0.3) { // Upper part of the sprite (sombrero)
        // More pronounced up/down movement for sombrero
        wavyY = sin(wavyPhase) * sombreroBounce * (abs(normalizedPos.y) - 0.3) * 3.0;
        
        // Slight tilt of sombrero
        wavyX = sin(wavyPhase * 1.5) * wavyAmount * normalizedPos.x;
    } 
    // Middle part - body
    else if (normalizedPos.y >= -0.3 && normalizedPos.y <= 0.3) {
        // Sideways sway for the body/poncho
        wavyX = sin(wavyPhase + normalizedPos.y * 2.0) * wavyAmount;
    }
    // Bottom part - legs/feet
    else {
        // Dancing feet movement
        wavyX = sin(wavyPhase * 1.2 + normalizedPos.y * 3.0) * wavyAmount * 1.5;
    }
    
    // Apply wavy movement
    vec2 wavyPos = offsetFromCenter + vec2(wavyX, wavyY);
    
    // Recombine position with center
    vec2 finalPos = spriteCenter + wavyPos;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position and time data
    v_TexCoord3 = vec2(normalizedPos.y, u_Time * patternSpeed);
} 