uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Metallic bronze parameters
float reflectionIntensity = 0.35; // Intensity of metallic reflections
float reflectionSharpness = 3.0; // Sharpness of reflection highlights (less sharp for bronze)
float patina = 0.15; // Amount of patina/oxidation

// Metal color definition
vec3 bronzeColor = vec3(0.8, 0.5, 0.2); // Rich bronze color
vec3 bronzeHighlight = vec3(1.0, 0.8, 0.5); // Bronze highlight
vec3 patinaColor = vec3(0.4, 0.65, 0.5); // Greenish patina color

// Create smooth bronze pattern with patina
float smoothBronzePattern(vec2 position, float time) {
    // Create flowing, aged bronze-specific wave patterns (no checkerboard)
    float wave1 = sin(position.x * 3.5 + position.y * 2.5 + time * 0.4) * 0.5 + 0.5;
    float wave2 = sin(position.x * 5.0 - position.y * 4.0 + time * 0.3) * 0.5 + 0.5;
    
    // Create slow swirl pattern for aged bronze
    float swirl = sin(atan(position.y, position.x) * 3.0 + length(position) * 7.0 + time * 0.3) * 0.5 + 0.5;
    
    // Create radial highlight patterns
    float radial = length(position);
    float radialPattern = sin(radial * 6.0 - time * 0.3) * 0.5 + 0.5;
    
    // Add directional light reflection - softer for bronze
    float angle = atan(position.y, position.x);
    float lightReflection = pow(sin(angle * 2.0 + time * 0.5) * 0.5 + 0.5, 1.5);
    
    // Blend all patterns for a rich bronze look
    return wave1 * 0.35 + wave2 * 0.25 + swirl * 0.2 + radialPattern * 0.1 + lightReflection * 0.1;
}

// Generate smooth patina effect without using checkerboard
float smoothPatina(vec2 position, float time) {
    // Patina forms in gradual patterns, especially in creases and edges
    
    // Create smooth edge gradient
    float edgeX = smoothstep(0.0, 0.4, abs(position.x)) * smoothstep(1.0, 0.6, abs(position.x));
    float edgeY = smoothstep(0.0, 0.4, abs(position.y)) * smoothstep(1.0, 0.6, abs(position.y));
    float edges = edgeX * edgeY;
    
    // Add flowing patina pattern
    float flowPattern = sin(position.x * 8.0 + position.y * 7.0 + time * 0.1) * 0.5 + 0.5;
    flowPattern *= sin(position.x * 5.0 - position.y * 6.0 - time * 0.08) * 0.5 + 0.5;
    
    // Create age spots
    float spots = sin(position.x * 12.0 + position.y * 14.0) * sin(position.y * 11.0 - position.x * 13.0);
    spots = smoothstep(0.7, 1.0, spots) * 0.5;
    
    // Combine all patina elements
    return max(max(1.0 - edges, flowPattern * 0.3), spots);
}

void main() {
    // Check if we're actually on the sprite
    vec4 originalColor = texture2D(u_Tex0, v_TexCoord);
    if(originalColor.a < 0.01) {
        discard;
    }
    
    // Get color mapping texture
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    
    // Sample texture with normal coordinates
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Get normalized position and time from vertex shader
    vec2 normalizedPos = v_TexCoord3.xy;
    float time = u_Time;
    
    // Calculate bronze reflection pattern without checkerboard
    float bronzePattern = smoothBronzePattern(normalizedPos, time);
    
    // Create patina effect without grid/checkerboard
    float patinaPattern = smoothPatina(normalizedPos, time);
    
    // Sharpen the highlights
    bronzePattern = pow(bronzePattern, reflectionSharpness);
    
    // Apply bronze color and reflection
    vec3 finalColor = mix(baseColor.rgb, bronzeColor, 0.5); // Bronze base color
    
    // Add patina to the edges and crevices
    finalColor = mix(finalColor, patinaColor, patinaPattern * patina);
    
    // Add bronze highlights
    finalColor += bronzeHighlight * bronzePattern * reflectionIntensity;
    
    // Set output color
    gl_FragColor = vec4(finalColor, baseColor.a);
} 