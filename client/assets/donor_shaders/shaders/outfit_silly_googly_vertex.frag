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

// Silly Googly parameters
float wobbleSpeed = 2.0; // Speed of wobble animation
float wobbleAmount = 0.03; // Amount of wobble
float bounceFrequency = 1.2; // How fast to bounce
float bounceHeight = 0.04; // How high to bounce

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create silly wobble effect
    float wobblePhase = u_Time * wobbleSpeed;
    float wobbleX = sin(wobblePhase + normalizedPos.y * 3.0) * wobbleAmount;
    float wobbleY = cos(wobblePhase * 0.7 + normalizedPos.x * 2.0) * wobbleAmount;
    
    // Apply wobble
    vec2 wobbledPos = offsetFromCenter + vec2(wobbleX, wobbleY) * length(normalizedPos);
    
    // Add a simple bounce
    float bounce = sin(u_Time * bounceFrequency) * bounceHeight;
    
    // Recombine position with center, wobble and bounce
    vec2 finalPos = spriteCenter + wobbledPos;
    finalPos.y -= bounce; // Apply bounce (subtract because y decreases going up)
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position and time
    v_TexCoord3 = vec2(length(normalizedPos), u_Time);
} 