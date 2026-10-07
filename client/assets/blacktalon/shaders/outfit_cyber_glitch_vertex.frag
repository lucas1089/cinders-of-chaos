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

// Cyber Glitch parameters
float glitchSpeed = 1.5; // Speed of glitch changes
float glitchIntensity = 0.008; // Amount of displacement
float glitchFrequency = 3.0; // Frequency of glitch changes

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Normalized position (-1 to 1)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Distance from center
    float distFromCenter = length(normalizedPos);
    
    // Create glitch effect
    // Use discrete time steps for sudden changes
    float glitchTime = floor(u_Time * glitchSpeed * 4.0) / 4.0;
    
    // Calculate horizontal glitch bands
    float horizontalBand = step(0.4, fract(normalizedPos.y * glitchFrequency + glitchTime * 3.7));
    
    // Calculate vertical glitch bands
    float verticalBand = step(0.7, fract(normalizedPos.x * glitchFrequency * 0.5 + glitchTime * 2.3));
    
    // Create diagonal glitch effect
    float diagonalGlitch = sin(normalizedPos.x * 5.0 + normalizedPos.y * 3.0 + glitchTime * 10.0);
    float diagonalBand = step(0.85, diagonalGlitch);
    
    // Combine glitch bands
    float glitchPattern = horizontalBand * 0.5 + verticalBand * 0.3 + diagonalBand * 0.2;
    
    // Create pixel shifting effect for cyber theme
    vec2 pixelShift = vec2(
        sin(glitchTime * 17.0 + normalizedPos.y * 13.0) * horizontalBand,
        cos(glitchTime * 13.0 + normalizedPos.x * 17.0) * verticalBand
    ) * glitchIntensity;
    
    // Digital data stream effect
    float dataStream = step(0.7, fract(normalizedPos.y * 20.0 - u_Time * 5.0));
    dataStream *= step(0.6, sin(normalizedPos.x * 30.0));
    
    // Add data stream displacement
    pixelShift.x += dataStream * sin(u_Time * 20.0) * glitchIntensity * 0.5;
    
    // Apply distortion based on glitch pattern and pixel shift
    vec2 finalPos = origPosition.xy + pixelShift;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass glitch information to fragment shader
    v_TexCoord3 = vec2(glitchPattern, dataStream);
} 