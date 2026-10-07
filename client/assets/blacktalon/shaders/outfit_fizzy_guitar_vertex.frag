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

// Fizzy Guitar parameters
float stringSpeed = 1.5; // Speed of string vibration
float stringAmplitude = 0.01; // Amount of string vibration
float stringCount = 7.0; // Number of guitar strings

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Normalized position (-1 to 1)
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate which string this vertex belongs to
    // Divide x space into stringCount regions
    float stringWidth = 2.0 / stringCount; // Width of each string region
    float stringIndex = floor((normalizedPos.x + 1.0) / stringWidth);
    
    // Calculate position within string (0 to 1)
    float posInString = fract((normalizedPos.x + 1.0) / stringWidth);
    
    // Calculate string vibration effect - each string vibrates differently
    float stringPhase = stringIndex / stringCount; // 0 to 1 phase offset per string
    float stringFreq = 1.0 + stringIndex * 0.2; // Slightly different frequency per string
    
    // Create guitar string vibration wave - varying with y position (like guitar string)
    float vibration = sin(normalizedPos.y * 5.0 + u_Time * stringSpeed * stringFreq + stringPhase * 6.28);
    
    // Apply varying amplitude based on y-position (tighter in middle like a plucked string)
    float yFactor = 1.0 - abs(normalizedPos.y) * 0.7; // More movement in middle of string
    vibration *= yFactor;
    
    // Apply different amplitudes to different strings
    float thisStringAmp = stringAmplitude * (0.8 + sin(stringIndex * 1.5) * 0.2);
    
    // Only apply vibration if close to the center of a string
    float stringEffect = smoothstep(0.3, 0.0, abs(posInString - 0.5)) * thisStringAmp;
    
    // Apply string vibration displacement
    vec2 finalPos = origPosition.xy + vec2(vibration * stringEffect, 0.0);
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass string information to fragment shader
    v_TexCoord3 = vec2(stringIndex / stringCount, stringEffect / thisStringAmp);
} 