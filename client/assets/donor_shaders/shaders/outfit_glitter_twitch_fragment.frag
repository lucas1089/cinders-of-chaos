uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Purple glitter parameters
vec3 glitterColor = vec3(0.6, 0.2, 0.9); // Rich purple 
vec3 glitterHighlight = vec3(0.9, 0.7, 1.0); // Light purple highlights
float glitterIntensity = 0.55;
float twitchSpeed = 12.0;

void main() {
    // Get main texture color
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    
    // Discard transparent pixels
    if(texColor.a < 0.01) discard;
    
    // Get color mapping for outfit colors
    vec4 texcolor2 = texture2D(u_Tex0, v_TexCoord2);
    
    // Apply outfit colors
    vec4 outfitColor = texColor;
    if(texcolor2.r > 0.9) {
        outfitColor *= texcolor2.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor2.g > 0.9) {
        outfitColor *= u_Color[2];
    } else if(texcolor2.b > 0.9) {
        outfitColor *= u_Color[3];
    }
    
    // Create twitchy glitter effect
    // First, create base glitter pattern based on texture coordinates
    float glitterPattern = fract(v_TexCoord3.x * 10.0 + v_TexCoord3.y * 12.0);
    
    // Add time-based twitching to the pattern
    float twitchX = sin(u_Time * twitchSpeed + v_TexCoord.y * 20.0) * 0.3;
    float twitchY = cos(u_Time * twitchSpeed * 1.2 + v_TexCoord.x * 15.0) * 0.3;
    float twitchFactor = sin((v_TexCoord.x + twitchX) * 30.0) * sin((v_TexCoord.y + twitchY) * 30.0);
    
    // Sharpen the glitter pattern and combine with twitch
    float glitterMask = step(0.8, glitterPattern * (twitchFactor * 0.5 + 0.7));
    
    // Create moving sparkles
    float sparklePhase = fract(v_TexCoord.x * 15.0 + v_TexCoord.y * 10.0 + u_Time * 2.0);
    float sparkle = pow(sparklePhase, 10.0) * 2.0; // Sharp sparkles
    
    // Combine glitter effect with sparkles
    float combinedGlitter = max(glitterMask * 0.7, sparkle);
    
    // Mix base colors with glitter
    vec3 finalColor = mix(outfitColor.rgb, glitterColor, 0.4); // Add purple base tint
    finalColor += glitterHighlight * combinedGlitter * glitterIntensity; // Add glitter highlights
    
    // Output final color
    gl_FragColor = vec4(finalColor, outfitColor.a);
} 