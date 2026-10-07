uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;
uniform vec2 u_Offset;
uniform float u_Time;

varying vec2 v_TexCoord;
varying vec2 v_FragCoord;
varying float v_Time;

void main()
{
    vec2 uv = v_TexCoord;
    float time = u_Time * 0.4;
    
    // Apply pixelate effect
    vec2 pixelSize = vec2(4.0, 4.0);
    vec2 uv_pixel = floor(uv * pixelSize) / pixelSize;
    
    // Waterfall color palette
    vec4 col1 = vec4(0.510, 0.776, 0.486, 1.0); // Light green
    vec4 col2 = vec4(0.200, 0.604, 0.318, 1.0); // Medium green
    vec4 col3 = vec4(0.145, 0.490, 0.278, 1.0); // Dark green
    vec4 col4 = vec4(0.059, 0.255, 0.251, 1.0); // Teal
    
    // Create displacement effect on Y-axis
    // Sample the texture itself for displacement
    vec3 displace = texture2D(u_Tex0, vec2(uv_pixel.x, (uv_pixel.y + time) * 0.05)).xyz;
    displace *= 0.5;
    displace.x -= 1.0;
    displace.y -= 1.0;
    displace.y *= 0.5;
    
    // Apply displacement to sample coordinates
    vec2 uv_tmp = uv_pixel;
    uv_tmp.y *= 0.2;
    uv_tmp.y += time;
    vec4 color = texture2D(u_Tex0, uv_tmp + displace.xy);
    
    // Match colors to palette
    vec4 noise = floor(color * 10.0) / 5.0;
    vec4 dark = mix(col1, col2, uv.y);
    vec4 bright = mix(col3, col4, uv.y);
    color = mix(dark, bright, noise);
    
    // Add gradients (darker at top, brighter at bottom)
    float inv_uv = 1.0 - uv_pixel.y;
    color.xyz -= 0.45 * pow(uv_pixel.y, 8.0);
    color.a -= 0.1 * pow(uv_pixel.y, 8.0);
    color += 0.5 * pow(inv_uv, 8.0);
    
    // Add wave effect
    float wave = sin(uv.x * 20.0 + time * 2.0) * 0.03;
    color.rgb += wave * vec3(0.1, 0.3, 0.5);
    
    // Add subtle scanlines
    float scanline = sin(uv.y * 100.0) * 0.02 + 0.98;
    color.rgb *= scanline;
    
    // Output final color
    gl_FragColor = color;
} 