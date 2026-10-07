attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_Position;
varying float v_Intensity;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Resolution;
uniform vec2 u_Center;
uniform float u_Time;

// Velvet texture parameters
vec2 effectTextureSize = vec2(675.0, 338.0);
vec2 direction = vec2(1.0,1.0);
float speed = 10.0;

// Enhanced parameters
float pulseSpeed = 2.0;
float pulseIntensity = 0.3;
float distortionAmount = 0.02;

// Bouncing balls parameters
const int NUM_BALLS = 3;
uniform vec2 ballPositions[NUM_BALLS];
uniform float ballSizes[NUM_BALLS];
varying vec2 v_BallPositions[NUM_BALLS];
varying float v_BallSizes[NUM_BALLS];

void main()
{
    // Create a pulsing effect (from velvet)
    float pulse = sin(u_Time * pulseSpeed) * pulseIntensity + 1.0;
    v_Intensity = pulse;
    
    // Add some distortion to the movement
    vec2 distortion = vec2(
        sin(u_Time * 1.5) * distortionAmount,
        cos(u_Time * 1.2) * distortionAmount
    );
    
    vec2 offset = (direction * speed * u_Time) + distortion;
    
    // Pass position for shimmering effect
    v_Position = a_Vertex.xy - u_Center;
    
    // Pass ball information to fragment shader
    for(int i = 0; i < NUM_BALLS; i++) {
        v_BallPositions[i] = ballPositions[i];
        v_BallSizes[i] = ballSizes[i];
    }
    
    // Apply the transformations
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1, 1);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord,1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset,1.0)).xy;
    v_TexCoord3 = ((a_TexCoord + offset) / effectTextureSize);
} 