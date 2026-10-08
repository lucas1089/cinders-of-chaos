uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform float u_spriteSize;

float outline_thickness = 0.15;
vec3 outline_colour = vec3(0.000, 0.783, 0.000); // colour here
float outline_threshold = .5;

void main()
{
	vec4 pixel = texture2D(u_Tex0, v_TexCoord);

    if (pixel.a <= outline_threshold) {
        // Use dFdx/dFdy to estimate pixel size (GLSL 1.10 compatible)
        vec2 pixelStep = abs(vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y)));
        if (pixelStep.x < 0.0001) pixelStep.x = 0.005;
        if (pixelStep.y < 0.0001) pixelStep.y = 0.005;

        float sum = 0.0;
        for (int n = 0; n < 9; ++n) {
            float offsetY = outline_thickness * float(n - 4) * pixelStep.y;
            float h_sum = 0.0;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(-4.0 * outline_thickness * pixelStep.x, offsetY)).a;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(-3.0 * outline_thickness * pixelStep.x, offsetY)).a;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(-2.0 * outline_thickness * pixelStep.x, offsetY)).a;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(-1.0 * outline_thickness * pixelStep.x, offsetY)).a;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(0.0, offsetY)).a;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(1.0 * outline_thickness * pixelStep.x, offsetY)).a;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(2.0 * outline_thickness * pixelStep.x, offsetY)).a;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(3.0 * outline_thickness * pixelStep.x, offsetY)).a;
            h_sum += texture2D(u_Tex0, v_TexCoord + vec2(4.0 * outline_thickness * pixelStep.x, offsetY)).a;
            sum += h_sum / 9.0;
        }

        vec3 outline_colour;
        outline_colour.r = 0.4 + abs(0.5 - mod(u_Time, 1.0));
        outline_colour.g = 0.0;
        outline_colour.b = 0.0;

        if (sum / 9.0 >= 0.0001) {
            pixel = vec4(outline_colour, 1);
        }
    }
	gl_FragColor = gl_FragColor + pixel;
}
