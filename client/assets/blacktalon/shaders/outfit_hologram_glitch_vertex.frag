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
float glitchStrength = 0.007;    // Strength of glitch displacement
float glitchSpeed = 3.0;         // Speed of glitch effects
float scanlineSpeed = 1.5;       // Speed of scanline movement

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
    
    // Create time variables for glitch effect
    float glitchTime = u_Time * glitchSpeed;
    
    // Create horizontal scanline effect - strong at particular y positions
    float scanlinePos = fract(glitchTime * scanlineSpeed) * 2.0 - 1.0;
    float scanline = smoothstep(0.03, 0.0, abs(normalizedPos.y - scanlinePos));
    
    // Create glitch blocks at different frequencies
    float blockGlitch1 = step(0.8, sin(normalizedPos.y * 15.0 + glitchTime * 3.1));
    float blockGlitch2 = step(0.95, sin(normalizedPos.y * 21.0 - glitchTime * 1.7));
    
    // Combine glitch effects with scanline
    float glitchFactor = scanline * 0.3 + blockGlitch1 * 0.1 + blockGlitch2 * 0.2;
    
    // Random-like glitch pattern
    float noiseX = sin(normalizedPos.y * 43.0 + glitchTime * 4.0);
    float noiseY = cos(normalizedPos.x * 37.0 + glitchTime * 2.5);
    
    // Apply horizontal shift for the glitch
    vec2 displacement = vec2(
        noiseX * glitchFactor * glitchStrength * 20.0,  // Stronger horizontal displacement
        noiseY * glitchFactor * glitchStrength * 5.0    // Subtle vertical displacement
    );
    
    // Add occasional big glitches
    float bigGlitch = step(0.98, sin(glitchTime * 0.5) * 0.5 + 0.5);
    displacement.x += bigGlitch * sin(normalizedPos.y * 20.0) * glitchStrength * 30.0;
    
    // Apply displacement to position
    vec2 finalPos = origPosition.xy + displacement * 24.0;
    
    // Calculate final position
    gl_Position = vec4((u_ProjectionMatrix * vec3(finalPos, 1.0)).xy, 1.0, 1.0);
    
    // Set texture coordinates for main texture with glitch effect
    vec2 texCoordGlitch = a_TexCoord;
    texCoordGlitch.x += bigGlitch * sin(a_TexCoord.y * 20.0) * 0.02;
    texCoordGlitch.x += blockGlitch2 * sin(a_TexCoord.y * 50.0) * 0.01;
    
    v_TexCoord = (u_TextureMatrix * vec3(texCoordGlitch, 1.0)).xy;
    
    // Set texture coordinates with offset (for color mapping)
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;
    
    // Pass additional information to fragment shader
    v_TexCoord3 = vec2(distFromCenter, angle);
} 