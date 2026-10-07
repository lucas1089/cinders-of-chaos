attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_MovementDir;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform float u_Time;

// Parameters for shadow trail
float fadeSpeed = 0.8; // Controls how quickly shadow movement updates

// Previous position tracking for movement direction
vec2 prevPosition = vec2(0.0, 0.0);
vec2 currPosition = vec2(0.0, 0.0);

void main() {
    // Calculate position
    vec3 transformedPos = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    gl_Position = vec4((u_ProjectionMatrix * transformedPos).xy, 1.0, 1.0);
    
    // Set texture coordinates
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Save normalized texture coordinates for smoke effect
    v_TexCoord3 = a_TexCoord;
    
    // Track current position for this vertex 
    currPosition = transformedPos.xy;
    
    // Calculate movement direction from time-based offset
    // We don't have actual movement info, so simulate based on time
    // This creates a common direction for all vertices in the outfit
    vec2 simulatedDir = vec2(sin(u_Time * 0.5), cos(u_Time * 0.3));
    
    // If we haven't established a previous position yet
    if (prevPosition.x == 0.0 && prevPosition.y == 0.0) {
        prevPosition = currPosition;
    }
    
    // Smoothly update movement direction
    v_MovementDir = mix(simulatedDir, normalize(currPosition - prevPosition), 0.1);
    
    // Store current position as previous for next frame
    prevPosition = mix(prevPosition, currPosition, fadeSpeed * 0.1);
} 