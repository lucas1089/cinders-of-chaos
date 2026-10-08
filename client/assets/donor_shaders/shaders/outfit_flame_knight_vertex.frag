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

// Flame Knight parameters
float flameHeight = 1.5; // Height of flames
float flameSpeed = 1.2; // Speed of flame animation
float flameIntensity = 0.01; // Intensity of flame distortion

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
    
    // Calculate angle from center
    float angle = atan(normalizedPos.y, normalizedPos.x);
    
    // Create flame effect at the bottom and sides of the character
    // Flames should be stronger at the bottom and fade as they rise
    float flameBase = smoothstep(-0.8, 0.0, normalizedPos.y); // Stronger at bottom
    
    // Add side flames
    float sideFactor = pow(abs(normalizedPos.x), 3.0) * (1.0 - abs(normalizedPos.y));
    float sideFlame = smoothstep(0.3, 0.9, sideFactor);
    
    // Combine flame bases
    float flameFactor = max(1.0 - flameBase, sideFlame) * smoothstep(1.0, 0.7, distFromCenter);
    
    // Create flame animation
    float flameTime = u_Time * flameSpeed;
    
    // Create multiple flame layers for more realistic look
    float flame1 = sin(normalizedPos.x * 4.0 + flameTime * 1.0) * 0.5 + 0.5;
    float flame2 = sin(normalizedPos.x * 7.0 - flameTime * 1.2 + 1.3) * 0.5 + 0.5;
    float flame3 = sin(normalizedPos.x * 5.0 + flameTime * 0.9 + 0.7) * 0.5 + 0.5;
    
    // Combine flame layers
    float flamePattern = flame1 * 0.5 + flame2 * 0.3 + flame3 * 0.2;
    
    // Calculate vertical flame displacement
    // Flames should move upward
    float flameDisplacement = flameFactor * flamePattern * flameHeight;
    
    // Apply upward displacement stronger at the edges
    vec2 displacement = vec2(
        sin(angle * 3.0 + flameTime) * flameFactor * flameIntensity, // Small horizontal flickering
        -flameDisplacement * flameIntensity * 1.5 // Upward movement (negative Y is up)
    );
    
    // Apply displacement to position
    vec2 finalPos = origPosition.xy + displacement;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass flame information to fragment shader
    v_TexCoord3 = vec2(flameFactor, flamePattern);
} 