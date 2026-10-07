attribute vec2 a_TexCoord;
attribute vec2 a_Vertex;
uniform mat3 u_TextureMatrix;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform mat3 u_TransformMatrix;
uniform mat3 u_ProjectionMatrix;
uniform vec2 u_Offset;
uniform vec2 u_Resolution;
uniform float u_Depth;
uniform float u_Time;

void main()
{
	// Apply time-based vertex jittering for unstable geometry
	vec2 jitter = vec2(
		sin(a_Vertex.x * 10.0 + u_Time * 4.0) * 0.02,
		cos(a_Vertex.y * 8.0 + u_Time * 3.0) * 0.02
	);
	
	vec2 distortedVertex = a_Vertex.xy + jitter;
	
	gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(distortedVertex, 1.0)).xy, u_Depth / 16384.0, 1.0);
	
	// Add warping to texture coordinates
	float warpIntensity = 0.03 * sin(u_Time * 2.7);
	vec2 texWarp = vec2(
		sin(a_TexCoord.y * 15.0 + u_Time * 5.1) * warpIntensity,
		cos(a_TexCoord.x * 12.0 + u_Time * 4.3) * warpIntensity
	);
	
	v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord + texWarp, 1.0)).xy;
	v_TexCoord2 = (u_TextureMatrix * vec3(a_TexCoord + u_Offset + texWarp * 1.5, 1.0)).xy;
	v_TexCoord3 = (u_TextureMatrix * vec3(u_Resolution, 1.0)).xy;
} 