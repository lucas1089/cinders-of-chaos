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

// Cursed parameters
float glitchSpeed = 5.0; // Speed of glitch effect
float glitchAmount = 0.01; // Amount of glitch distortion
float twitchSpeed = 8.0; // Speed of twitchy movement
float twitchAmount = 0.008; // Amount of twitchy movement

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position (-1 to 1 range)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Create glitch effect for random groups of vertices
    // Create different glitch zones that shift over time
    float glitchZone1 = step(0.7, fract(normalizedPos.y * 4.0 + u_Time * 0.3));
    float glitchZone2 = step(0.8, fract(normalizedPos.x * 3.0 - u_Time * 0.4));
    float glitchZone3 = step(0.75, fract(normalizedPos.x * 2.0 + normalizedPos.y * 3.0 + u_Time * 0.5));
    
    // Combine glitch zones
    float glitchZone = max(glitchZone1, max(glitchZone2, glitchZone3));
    
    // Generate glitch offset
    vec2 glitchOffset = vec2(0.0);
    if(glitchZone > 0.0) {
        // Apply horizontal glitchy offset
        glitchOffset.x = sin(u_Time * glitchSpeed + normalizedPos.y * 10.0) * glitchAmount;
        
        // Apply occasional vertical glitchy offset
        if(fract(u_Time * 1.7) > 0.8) {
            glitchOffset.y = cos(u_Time * glitchSpeed * 1.5 + normalizedPos.x * 8.0) * glitchAmount * 0.5;
        }
    }
    
    // Add twitchy movement that affects the entire sprite occasionally
    float twitchX = 0.0;
    float twitchY = 0.0;
    
    // Random twitch pulses
    float twitchPulse1 = pow(sin(u_Time * twitchSpeed) * 0.5 + 0.5, 4.0); // Sharp pulse
    float twitchPulse2 = pow(sin(u_Time * twitchSpeed * 1.3) * 0.5 + 0.5, 5.0); // Another pulse
    
    // Apply twitches
    twitchX = (sin(u_Time * twitchSpeed * 2.0) * twitchPulse1 + 
               cos(u_Time * twitchSpeed * 3.0) * twitchPulse2) * twitchAmount;
               
    twitchY = (cos(u_Time * twitchSpeed * 2.5) * twitchPulse1 + 
               sin(u_Time * twitchSpeed * 2.7) * twitchPulse2) * twitchAmount;
    
    // Combine offsets
    vec2 finalOffset = glitchOffset + vec2(twitchX, twitchY);
    
    // Calculate final position with offset
    vec2 finalPos = origPosition.xy + finalOffset;
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Add some distortion to one set of texture coordinates to create the displaced look
    vec2 texDistortion = vec2(
        sin(normalizedPos.y * 10.0 + u_Time * 3.0) * 0.01,
        cos(normalizedPos.x * 8.0 + u_Time * 2.5) * 0.01
    ) * glitchZone;
    
    // Pass normalized position, glitch zone, and distorted texture coords
    v_TexCoord3 = vec2(glitchZone, u_Time);
} 