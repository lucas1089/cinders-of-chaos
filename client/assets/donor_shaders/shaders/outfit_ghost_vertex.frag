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

// Ghost parameters
float floatSpeed = 0.8; // Speed of floating movement
float floatAmount = 0.01; // Amount of floating movement
float trailLength = 0.05; // Length of trailing effect

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create gentle floating movement
    float floatOffset = sin(u_Time * floatSpeed + normalizedPos.x * 2.0) * floatAmount;
    
    // Apply vertical floating motion that's stronger at the top of the sprite
    float verticalFactor = max(0.0, normalizedPos.y); // More effect at the top (positive y)
    vec2 floatMove = vec2(0.0, floatOffset * (verticalFactor + 0.5));
    
    // Add slight wavy trail effect
    float trailPhase = sin(normalizedPos.y * 5.0 + u_Time * 2.0) * 0.5 + 0.5;
    float trailFactor = max(0.0, -normalizedPos.y); // More trail at the bottom (negative y)
    vec2 trailOffset = vec2(
        sin(u_Time * 2.0 + normalizedPos.y * 3.0) * trailLength,
        0.0
    ) * trailFactor * trailPhase;
    
    // Calculate final position with effects
    vec2 finalPos = origPosition.xy + floatMove + trailOffset;
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized position, trail factors and time to fragment shader
    v_TexCoord3 = vec3(normalizedPos.x, normalizedPos.y, u_Time).xy;
} 