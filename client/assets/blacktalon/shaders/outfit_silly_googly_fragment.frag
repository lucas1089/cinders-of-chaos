uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Silly Googly parameters
float eyeSize = 0.12; // Size of googly eyes
float pupilSize = 0.05; // Size of pupils
float colorShiftAmount = 0.1; // Amount of color shifting

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample texture with normal coordinates
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Extract data from v_TexCoord3
    float distFromCenter = v_TexCoord3.x; // Distance from center
    float currentTime = v_TexCoord3.y; // Time
    
    // Determine positions for googly eyes
    vec2 leftEyeCenter = vec2(0.25, 0.3); // Left eye position in texture space
    vec2 rightEyeCenter = vec2(0.75, 0.3); // Right eye position in texture space
    
    // Calculate pupil position with silly bouncing movement
    float pupilPhaseX = sin(currentTime * 2.0) * 0.6;
    float pupilPhaseY = cos(currentTime * 1.7) * 0.6;
    
    // Apply silly color shifting
    float colorShift = sin(currentTime * 1.5) * colorShiftAmount;
    baseColor.rgb = mix(baseColor.rgb, 
                     vec3(baseColor.r + colorShift, 
                          baseColor.g - colorShift, 
                          baseColor.b + colorShift), 0.5);
    
    // Draw eyes only on the upper part of the sprite
    if (v_TexCoord.y < 0.5) {
        // Check if we're inside the left eye
        float leftEyeDist = distance(v_TexCoord, leftEyeCenter);
        if (leftEyeDist < eyeSize) {
            // Draw white of eye
            baseColor.rgb = vec3(0.9, 0.9, 0.9);
            
            // Calculate wobbling pupil position
            vec2 leftPupilOffset = vec2(pupilPhaseX, pupilPhaseY) * (eyeSize - pupilSize);
            vec2 leftPupilCenter = leftEyeCenter + leftPupilOffset;
            
            // Draw pupil
            float leftPupilDist = distance(v_TexCoord, leftPupilCenter);
            if (leftPupilDist < pupilSize) {
                baseColor.rgb = vec3(0.1, 0.1, 0.1);
            }
        }
        
        // Check if we're inside the right eye
        float rightEyeDist = distance(v_TexCoord, rightEyeCenter);
        if (rightEyeDist < eyeSize) {
            // Draw white of eye
            baseColor.rgb = vec3(0.9, 0.9, 0.9);
            
            // Calculate wobbling pupil position - slightly different movement for second eye
            vec2 rightPupilOffset = vec2(pupilPhaseX * 0.8, pupilPhaseY * 1.2) * (eyeSize - pupilSize);
            vec2 rightPupilCenter = rightEyeCenter + rightPupilOffset;
            
            // Draw pupil
            float rightPupilDist = distance(v_TexCoord, rightPupilCenter);
            if (rightPupilDist < pupilSize) {
                baseColor.rgb = vec3(0.1, 0.1, 0.1);
            }
        }
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 