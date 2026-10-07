// Transmute Transition - Hide Shader (Old Sprite - shows bottom portion)
// This shader hides the OLD sprite from top to bottom during transition

uniform sampler2D u_Tex0;
uniform float u_Time;
uniform float u_var0;  // Transition progress: 0.0 = fully visible, 1.0 = fully hidden
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;

// Configuration
const float LINE_WIDTH = 0.025;      // Width of the transition line
const float ALPHA_THRESHOLD = 0.01;  // Minimum alpha to render

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Calculate position (0 = top, 1 = bottom)
    float pixelY = 1.0 - v_TexCoord.y;

    // The hide line position based on transition progress
    float hidePos = u_var0;

    // If pixel is ABOVE the hide line, discard it (new sprite shows there)
    if (pixelY < hidePos - LINE_WIDTH) {
        discard;
    }

    gl_FragColor = texColor;
    if (gl_FragColor.a < ALPHA_THRESHOLD) discard;
}
