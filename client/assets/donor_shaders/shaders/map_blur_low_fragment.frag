uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec2 u_Resolution;
uniform float u_Time;

// Low blur parameters
float blurRadius = 1.0;
float blurSigma = 1.5;
const int kernelSize = 5;

void main() {
    // Get pixel size for sampling
    vec2 pixelSize = 1.0 / u_Resolution;
    
    // Initialize color
    vec4 color = vec4(0.0);
    float weightSum = 0.0;
    
    // Create a 5x5 Gaussian blur kernel (25 samples)
    for (int y = -kernelSize/2; y <= kernelSize/2; y++) {
        for (int x = -kernelSize/2; x <= kernelSize/2; x++) {
            // Calculate Gaussian weight
            float distSq = float(x*x + y*y);
            float weight = exp(-distSq / (2.0 * blurSigma * blurSigma));
            
            // Sample texture with offset
            vec2 offset = vec2(float(x), float(y)) * pixelSize * blurRadius;
            vec4 sampled = texture2D(u_Tex0, v_TexCoord + offset);
            
            // Accumulate
            color += sampled * weight;
            weightSum += weight;
        }
    }
    
    // Normalize by sum of weights
    color /= weightSum;
    
    // Output blurred color
    gl_FragColor = color;
} 