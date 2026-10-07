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

// Fizzy parameters
float fizzSpeed = 1.5; // Speed of bubbles
float fizzAmount = 0.008; // Amount of fizz displacement
float fizzFrequency = 15.0; // Frequency of fizz

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate fizzy displacement
    // Create noise-like displacement based on position and time
    float fizz1 = sin(normalizedPos.x * fizzFrequency + normalizedPos.y * fizzFrequency * 1.5 + u_Time * fizzSpeed);
    float fizz2 = cos(normalizedPos.y * fizzFrequency * 0.8 + normalizedPos.x * fizzFrequency * 1.2 + u_Time * fizzSpeed * 1.3);
    float fizz3 = sin(normalizedPos.x * fizzFrequency * 0.5 + normalizedPos.y * fizzFrequency * 0.7 + u_Time * fizzSpeed * 0.7);
    
    // Combine fizz displacement
    float fizzDisplacementX = fizz1 * fizz2 * fizzAmount;
    float fizzDisplacementY = fizz2 * fizz3 * fizzAmount;
    
    // Create rising bubble effect
    // Different parts of the sprite have bubbles rising at different times
    float bubblePhase = fract(normalizedPos.x * 0.5 + u_Time * 0.1);
    float bubbleStrength = sin(bubblePhase * 3.14159 * 2.0) * 0.5 + 0.5;
    
    // Bubbles rise upward
    fizzDisplacementY += bubbleStrength * fizzAmount * 2.0;
    
    // Apply fizzy displacement
    vec2 finalPos = origPosition.xy + vec2(fizzDisplacementX, fizzDisplacementY);
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position and bubbleStrength for fragment shader
    v_TexCoord3 = vec2(length(normalizedPos), bubbleStrength);
} 