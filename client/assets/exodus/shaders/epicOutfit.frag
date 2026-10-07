varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;
uniform int u_outfitSize;
uniform mat4 u_Color;

float oscillation = (sin(u_Time) + 1) / 2; // range: 0 to 1
float thickness = 1 - (0.5 * oscillation); // range: 0.5 to 1
vec3 glowColor = vec3(0.0, 0.6, 1.0); // color
float threshold = .9; // default : .8

void main()
{
    vec4 item = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    if(texcolor.r > 0.9) {
        item *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(item.g > 0.9) {
        item *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        item *= u_Color[3];
    }

    vec4 effect = texture2D(u_Tex1, v_TexCoord);

    vec4 effectColor = vec4(0.0, 0.6, 1.0, 1.0);
    effect = effect * effectColor;

    float effectIntensity = 0.9;
    effect = effect * effectIntensity;

    // Attach effect on item
    if(item.a) {
        item += effect;
    }

    vec4 outerblur;
    
    if (item.a <= threshold) {
        ivec2 size = textureSize(u_Tex0, 0);
        float uv_x = v_TexCoord.x * size.x;
        float uv_y = v_TexCoord.y * size.y;

        // If used on Item, so we not passing u_outfitSize on item, so should be 32 by default
        if (u_outfitSize <= 0) {
            u_outfitSize = 32;
        }

        float sum = 0.0;
        float scaledThicknessBlur = (u_outfitSize, u_outfitSize) * thickness / u_outfitSize;
        for (int n = 0; n < 9; ++n) {
            uv_y = (v_TexCoord.y * size.y) + (scaledThicknessBlur * float(n - 4.5));
            float h_sum = 0.0;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x - (4.0 * scaledThicknessBlur), uv_y), 0).a;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x - (3.0 * scaledThicknessBlur), uv_y), 0).a;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x - (2.0 * scaledThicknessBlur), uv_y), 0).a;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x - scaledThicknessBlur, uv_y), 0).a;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x, uv_y), 0).a;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x + scaledThicknessBlur, uv_y), 0).a;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x + (2.0 * scaledThicknessBlur), uv_y), 0).a;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x + (3.0 * scaledThicknessBlur), uv_y), 0).a;
            h_sum += texelFetch(u_Tex0, ivec2(uv_x + (4.0 * scaledThicknessBlur), uv_y), 0).a;
            sum += h_sum / 9.0;
        }

        outerblur = vec4(glowColor, (sum / 9.0) * threshold);
    }

    vec4 result = max(item, outerblur);
    
    if(result.a < 0.01) discard;
    
    gl_FragColor = result;
}