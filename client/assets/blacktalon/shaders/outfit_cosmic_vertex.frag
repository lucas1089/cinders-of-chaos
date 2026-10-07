attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;
uniform float u_Time;

// Cosmic flow parameters
varying float v_FlowIntensity;
varying vec2 v_FlowDirection;
varying float v_CosmicPhase;
varying float v_OrbPhase;
varying float v_DistanceFromCenter;
varying float v_ExplosionPhase;

void main()
{
    // Create flowing effect with cosmic twist
    v_FlowIntensity = sin(u_Time * 0.8) * 0.2 + 0.8;
    v_FlowDirection = vec2(
        sin(u_Time * 0.5) * 0.2,
        cos(u_Time * 0.7) * 0.2
    );

    // Calculate cosmic phase for color transitions
    v_CosmicPhase = mod(u_Time * 0.3, 1.0);

    // Calculate additional phases for stargaze shader
    v_OrbPhase = mod(u_Time * 0.5, 1.0);
    v_DistanceFromCenter = length(a_TexCoord - vec2(0.5, 0.5));
    v_ExplosionPhase = mod(u_Time * 0.4 + 0.5, 1.0);

    // Apply the transformations
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;

    // Add cosmic motion with spiral effect
    float spiral = length(a_Vertex - u_Center) * 0.5;
    float angle = atan(a_Vertex.y - u_Center.y, a_Vertex.x - u_Center.x);
    float spiralOffset = sin(spiral + angle + u_Time * 0.5) * 0.02;

    v_TexCoord3 = v_TexCoord + vec2(
        sin(u_Time * 0.4 + v_TexCoord.y * 10.0 + spiralOffset) * 0.02,
        cos(u_Time * 0.3 + v_TexCoord.x * 8.0 + spiralOffset) * 0.02
    );

    // Additional texture coordinate for overtexture effect
    v_TexCoord4 = v_TexCoord + vec2(
        sin(u_Time * 0.6 + v_TexCoord.y * 8.0) * 0.03,
        cos(u_Time * 0.5 + v_TexCoord.x * 6.0) * 0.03
    );
} 