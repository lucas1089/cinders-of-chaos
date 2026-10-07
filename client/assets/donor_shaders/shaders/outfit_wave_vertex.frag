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

// Wave parameters
float waveSpeed = 2.0; // Speed of wave animation
float waveAmplitude = 0.008; // Height of waves
float waveFrequency = 10.0; // How many waves
float flowSpeed = 1.5; // Speed of flow direction

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite (assuming sprites are ~48x48 pixels)
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate wave effect
    float time = u_Time * waveSpeed;
    float flowOffset = u_Time * flowSpeed;
    
    // Create flowing wave pattern
    // Vertical position affects wave phase
    float wave = sin((offsetFromCenter.y * waveFrequency + flowOffset) * 0.5) * waveAmplitude;
    
    // Apply wave distortion horizontally
    vec2 wavePos = offsetFromCenter;
    wavePos.x += wave;
    
    // Add secondary wave for more interesting effect
    wave = cos((offsetFromCenter.x * waveFrequency * 0.7 + time) * 0.5) * waveAmplitude * 0.7;
    wavePos.y += wave;
    
    // Recombine with center
    vec2 finalPos = spriteCenter + wavePos;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Additional texture coordinates
    v_TexCoord3 = v_TexCoord;
} 