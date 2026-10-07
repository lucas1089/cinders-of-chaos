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

// How fast the rainbow spectrum scrolls across the sprite.
float rainbowSpeed = 0.35;

void main() {
    // Transformed vertex position (no distortion - effect lives in the fragment).
    vec3 origPosition = u_TransformMatrix * vec3(a_Vertex.xy, 1.0);
    gl_Position = vec4((u_ProjectionMatrix * origPosition).xy, 1.0, 1.0);

    // Main texture coordinates.
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;

    // Offset coordinates used for the outfit color-mapping mask.
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset, 1.0)).xy;

    // Pass animated time to the fragment shader.
    v_TexCoord3 = vec2(u_Time * rainbowSpeed, 0.0);
}
