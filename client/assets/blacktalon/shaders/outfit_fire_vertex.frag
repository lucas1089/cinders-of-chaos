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

// Fire movement parameters
float fireWaveSpeed = 3.0;
float fireWaveIntensity = 0.005; // Reduced for subtler effect
float verticalFlowSpeed = 0.1;   // Speed of upward flame flow

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate just the flame flickering (no rotation)
    float verticalPos = offsetFromCenter.y;
    
    // More intense flickering at the top of the sprite
    float intensityFactor = 1.0 - (verticalPos / 24.0);
    
    // Calculate waves without rotation
    float waveX = sin(u_Time * fireWaveSpeed + verticalPos * 10.0) * fireWaveIntensity * intensityFactor;
    
    // Apply subtle horizontal flickering
    offsetFromCenter.x += waveX * 2.0;
    
    // Recombine with center
    vec2 modifiedPos = spriteCenter + offsetFromCenter;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(modifiedPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates for fire effect - vertical flow only, no rotation
    v_TexCoord3 = v_TexCoord + vec2(0.0, u_Time * verticalFlowSpeed);
} 