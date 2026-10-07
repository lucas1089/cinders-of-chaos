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

// Parameters
float dataFlowSpeed = 2.0;      // Speed of data flow animation
float pulseStrength = 0.005;    // Amount of pulsing effect
float dataGridDensity = 2.0;    // Density of data grid pattern

void main() {
    // Get transformed vertex position
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    
    // Find approximate center of the sprite
    vec2 spriteCenter = floor(origPosition.xy / 48.0) * 48.0 + vec2(24.0, 24.0);
    
    // Calculate offset from center
    vec2 offsetFromCenter = origPosition.xy - spriteCenter;
    
    // Calculate normalized position
    vec2 normalizedPos = offsetFromCenter / 24.0;
    
    // Calculate distance from center and angle
    float distFromCenter = length(normalizedPos);
    float angle = atan(normalizedPos.y, normalizedPos.x);
    
    // Create digital data flow effect
    float timeScale = u_Time * dataFlowSpeed;
    
    // Create grid-like coordinates for cyber matrix effect
    vec2 gridPos = normalizedPos * dataGridDensity;
    float gridX = fract(gridPos.x);
    float gridY = fract(gridPos.y);
    
    // Create pulsing based on grid pattern
    float gridPattern = step(0.9, gridX) + step(0.9, gridY);
    
    // Create data flow displacement along grid lines
    float flowX = fract(floor(gridPos.x) * 0.1 + timeScale * 0.2);
    float flowY = fract(floor(gridPos.y) * 0.1 - timeScale * 0.3);
    
    float flowPulse = (sin(flowX * 6.28) * 0.5 + 0.5) * step(0.95, gridY);
    flowPulse += (sin(flowY * 6.28) * 0.5 + 0.5) * step(0.95, gridX);
    
    // Digital pulse displacement effect
    vec2 displacement = vec2(0.0);
    
    // Add data flow movement along grid lines
    displacement.x += sin(gridPos.y * 3.14 + timeScale) * step(0.9, gridY) * pulseStrength * 2.0;
    displacement.y += cos(gridPos.x * 3.14 - timeScale * 0.7) * step(0.9, gridX) * pulseStrength * 2.0;
    
    // Add overall subtle digital pulsing 
    float globalPulse = sin(timeScale) * 0.5 + 0.5;
    displacement += normalizedPos * sin(distFromCenter * 5.0 - timeScale) * pulseStrength * globalPulse;
    
    // Apply occasional data packet bursts
    float dataBurst = step(0.97, sin(timeScale * 0.3 + distFromCenter * 10.0) * 0.5 + 0.5);
    displacement += normalizedPos * dataBurst * pulseStrength * 5.0;
    
    // Apply displacement to position
    vec2 finalPos = origPosition.xy + displacement * 24.0;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    
    // Add subtle UV distortion for data flow effect
    vec2 texCoordOffset = vec2(0.0);
    texCoordOffset.x += sin(a_TexCoord.y * 20.0 + timeScale * 2.0) * 0.002 * dataBurst;
    texCoordOffset.y += cos(a_TexCoord.x * 20.0 - timeScale * 1.5) * 0.002 * dataBurst;
    
    // Apply texture distortion
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord + texCoordOffset, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass additional information to fragment shader
    v_TexCoord3 = vec2(distFromCenter, angle);
} 