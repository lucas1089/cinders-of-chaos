attribute vec2 a_TexCoord;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying float v_Time;
attribute vec2 a_Vertex;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Center;
uniform float u_Time;

vec2 effectTextureSize = vec2(609.0, 559.0);
vec2 direction = vec2(0.7, 0.7);
float speed = 15.0;
float angle = 120.0;

vec2 rotate(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	mat2 m = mat2(c, -s, s, c);
	return m * v;
}

void main()
{
    // Dynamic direction change for swirling effect
    float dynAngle = angle + sin(u_Time * 0.5) * 45.0;
    vec2 dynDirection = rotate(direction, (dynAngle / 180.0) * 3.14);
    
    vec2 offset = dynDirection * speed * u_Time;
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex.xy, 1.0)).xy, 1.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord,1.0)).xy;
    v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset,1.0)).xy;
    
    // Add swirling spiral effect to texture coordinates
    float spiralFactor = 0.03 * sin(u_Time * 0.8);
    vec2 centerPoint = vec2(0.5, 0.5);
    vec2 tc = a_TexCoord - centerPoint;
    float dist = length(tc);
    float spiral = atan(tc.y, tc.x) + dist * 10.0 * spiralFactor + u_Time * 1.5;
    float s = sin(spiral);
    float c = cos(spiral);
    tc = mat2(c, -s, s, c) * tc;
    tc += centerPoint;
    
    v_TexCoord3 = ((tc + rotate(dynDirection, (dynAngle / 180.0) * 3.14) * u_Time * speed) / effectTextureSize);
    v_Time = u_Time;
} 