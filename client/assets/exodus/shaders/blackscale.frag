#if __VERSION__ < 130
#define TEXTURE2D texture2D
#else
#define TEXTURE2D texture
#endif

uniform float u_GlobalTime;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

uniform vec2 u_Resolution;
uniform float u_float1;	/* period time */
uniform float u_float2;	/* start time */

#define M_PI     3.1415926535897932384626433832795
#define M_TWO_PI 6.2831853071795864769252867665590

const vec3 grayScaleMultiplier = vec3(0.299, 0.587, 0.114);

void main(){
	/* Position */
	vec2 position = v_TexCoord - vec2(0.5);

	/* Current angle */
	float percentage = min((u_GlobalTime - u_float2) / u_float1, 1.0);
	percentage = max(0.0, percentage);
	float currAngle = percentage * M_TWO_PI;

	/* background images */
	vec4 image = TEXTURE2D(u_Tex0, v_TexCoord);
	vec3 gray = vec3(dot(image.rgb, grayScaleMultiplier)) - 0.2; // 0.2 to have darker image

	/* Circle sector */
	float a = atan(-position.x, -position.y);
	a = step(sign(a), 0.0) * M_TWO_PI + a;
	float sector = 1.0 - smoothstep(currAngle - 0.1, currAngle + 0.1, M_TWO_PI - a);

	if (sector == 0.0) {
		gl_FragColor = vec4(gray, image.a);
	} else {
		gl_FragColor = vec4(image);
	}
}