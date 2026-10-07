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

// Poisoned effect parameters
float poisonWobbleSpeed = 0.7;     // Speed of poison wobble
float poisonWobbleAmount = 0.0025; // Subtle amount of wobble

void main() {
    // Calculate vertex position
    vec3 originalPos = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Apply subtle poisoned wobble effect to simulate sickness
    vec2 modifiedPos = originalPos.xy;
    
    // Create wobble based on vertex position and time
    float wobbleX = sin(u_Time * poisonWobbleSpeed + originalPos.y * 0.1);
    float wobbleY = cos(u_Time * poisonWobbleSpeed * 1.3 + originalPos.x * 0.1);
    
    // Apply wobble
    modifiedPos += vec2(wobbleX, wobbleY) * poisonWobbleAmount;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(modifiedPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass normalized texture coordinates to fragment shader
    v_TexCoord3 = a_TexCoord;
} 