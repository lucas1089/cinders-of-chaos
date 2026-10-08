uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Jello parameters
float wobbleSpeed = 2.0; // Speed of wobbling
float wobbleIntensity = 0.015; // Intensity of wobble
float waveCount = 2.0; // Number of waves in the effect

void main() {
    // Check if we're actually on the sprite by sampling original texture
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Calculate jello distortion
    float time = u_Time * wobbleSpeed;
    
    // Create wobble effect - uses sin waves in both directions
    vec2 wobbleOffset;
    wobbleOffset.x = sin(time + v_TexCoord.y * waveCount * 6.28) * wobbleIntensity;
    wobbleOffset.y = cos(time * 1.2 + v_TexCoord.x * waveCount * 6.28) * wobbleIntensity;
    
    // Add secondary wobble for more jello-like effect
    wobbleOffset.x += cos(time * 0.8 + v_TexCoord.y * waveCount * 4.5) * wobbleIntensity * 0.4;
    wobbleOffset.y += sin(time * 0.9 + v_TexCoord.x * waveCount * 4.5) * wobbleIntensity * 0.4;
    
    // Apply distortion to texture coordinates
    vec2 distortedCoord = v_TexCoord + wobbleOffset;
    
    // Sample texture with jello coords
    vec4 baseColor = texture2D(u_Tex0, distortedCoord);
    
    // If distortion led to transparent pixel, try to recover by moving less far
    if (baseColor.a < 0.01) {
        // Sample with half the distortion to avoid black edges
        distortedCoord = v_TexCoord + wobbleOffset * 0.5;
        baseColor = texture2D(u_Tex0, distortedCoord);
    }
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Add slight color shift for jello-like effect 
    float colorShift = sin(time * 0.5) * 0.05;
    baseColor.r += colorShift;
    baseColor.g -= colorShift * 0.5;
    baseColor.b += colorShift * 0.3;
    
    // Set output color
    gl_FragColor = baseColor;
} 