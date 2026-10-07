uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
varying vec2 v_TexCoord4;
varying float v_FlowIntensity;
varying vec2 v_FlowDirection;
varying float v_CosmicPhase;
varying float v_ExplosionPhase;
varying float v_DistanceFromCenter;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform sampler2D u_Tex2;
uniform vec2 u_Resolution;
uniform float u_Time;

// Effect parameters
float flowSpeed = 0.8;
float flowIntensity = 0.9;
float cosmicIntensity = 1.0;
float starsIntensity = 1.2;
float overtextureIntensity = 1.0;

// Lava color palette function
vec3 lavaPalette(float t) {
    // Lava-like color palette
    vec3 darkRed = vec3(0.8, 0.1, 0.0);
    vec3 brightRed = vec3(1.0, 0.2, 0.0);
    vec3 orange = vec3(1.0, 0.5, 0.0);
    vec3 yellow = vec3(1.0, 0.8, 0.0);
    vec3 white = vec3(1.0, 0.9, 0.8);
    
    // Oscillate through lava colors
    t = fract(t);
    
    if (t < 0.2) {
        return mix(darkRed, brightRed, t * 5.0);
    } else if (t < 0.4) {
        return mix(brightRed, orange, (t - 0.2) * 5.0);
    } else if (t < 0.6) {
        return mix(orange, yellow, (t - 0.4) * 5.0);
    } else if (t < 0.8) {
        return mix(yellow, white, (t - 0.6) * 5.0);
    } else {
        return mix(white, darkRed, (t - 0.8) * 5.0);
    }
}

// Enhanced plasma function with lava-like flow
vec4 lavaPlasma(vec4 txt, vec2 uv, float speed) {
    float timeX = u_Time * speed;
    
    // Create flowing lava-like pattern
    float a = 1.1 + timeX * 1.5;
    float b = 0.5 + timeX * 1.2;
    float c = 8.4 + timeX * 1.0;
    float d = 3.2 + timeX * 0.8;
    
    // Calculate distance from center
    vec2 center = vec2(0.5, 0.5);
    float dist = length(uv - center);
    
    // Create flowing lava pattern
    float plasma = 
        sin(a + dist * 12.0) * 0.5 + 0.5 +
        sin(b - dist * 10.0) * 0.5 + 0.5 +
        sin((c + dist * 18.0) * 0.5) * 0.5 + 0.5 +
        sin(d + dist * 25.0) * 0.5 + 0.5;
    
    plasma = plasma * 0.3;
    
    // Apply lava color palette
    vec3 lavaColor = lavaPalette(plasma + v_CosmicPhase);
    
    // Add bright ember effect
    float ember = sin(plasma * 25.0 + timeX * 5.0) * 0.5 + 0.5;
    lavaColor += vec3(1.0, 0.5, 0.0) * ember * 0.4;
    
    return vec4(mix(txt.rgb, lavaColor, flowIntensity), txt.a);
}

void main() {
    // Sample textures
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 starsEffect = texture2D(u_Tex1, v_TexCoord3);
    vec4 overtextureEffect = texture2D(u_Tex2, v_TexCoord4);
    
    // Apply outfit colors
    if(texcolor.r > 0.9) {
        baseColor *= texcolor.g > 0.9 ? u_Color[0] : u_Color[1];
    } else if(texcolor.g > 0.9) {
        baseColor *= u_Color[2];
    } else if(texcolor.b > 0.9) {
        baseColor *= u_Color[3];
    }
    
    // Initialize with base color
    gl_FragColor = baseColor;
    
    if(texcolor.a > 0.9) {
        // Calculate explosion effect
        float explosionStrength = 0.0;
        if (v_ExplosionPhase < 1.0) {
            explosionStrength = smoothstep(0.0, 1.0, v_ExplosionPhase);
        } else if (v_ExplosionPhase < 2.0) {
            explosionStrength = smoothstep(1.0, 0.0, v_ExplosionPhase - 1.0);
        }
        
        // Create blended effect
        vec3 combinedEffect = mix(
            starsEffect.rgb * starsIntensity,
            overtextureEffect.rgb * overtextureIntensity,
            sin(u_Time * 0.5) * 0.5 + 0.5
        );
        
        // Apply lava plasma effect
        vec4 plasmaEffect = lavaPlasma(baseColor, v_TexCoord + v_FlowDirection, flowSpeed);
        
        // Apply flow intensity
        gl_FragColor = mix(baseColor, plasmaEffect, v_FlowIntensity);
        
        // Add bright lava glow
        float glow = sin(u_Time * 1.5) * 0.2 + 0.2;
        vec3 glowColor = lavaPalette(u_Time * 0.2);
        gl_FragColor.rgb += glowColor * glow * baseColor.a;
        
        // Apply bright lava edge highlight
        float edgeHighlight = 
            sin(v_TexCoord.x * 25.0 + u_Time * 2.5) * 0.5 + 0.5 + 
            cos(v_TexCoord.y * 20.0 + u_Time * 2.0) * 0.5 + 0.5;
        edgeHighlight = pow(edgeHighlight * 0.6, 2.0) * 0.15;
        
        // Add bright ember effect to edges
        float ember = sin(edgeHighlight * 20.0 + u_Time * 4.0) * 0.5 + 0.5;
        vec3 edgeColor = mix(lavaPalette(u_Time * 0.1), vec3(1.0, 0.5, 0.0), ember);
        gl_FragColor.rgb += edgeColor * edgeHighlight;
        
        // Add bright lava field effect
        float lavaField = sin(v_TexCoord.x * 120.0 + u_Time * 2.5) * 0.5 + 0.5;
        lavaField *= sin(v_TexCoord.y * 120.0 + u_Time * 2.0) * 0.5 + 0.5;
        lavaField = pow(lavaField, 8.0) * 0.6;
        gl_FragColor.rgb += vec3(1.0, 0.5, 0.0) * lavaField;
        
        // Apply inverted explosion effect
        float explosionGlow = smoothstep(0.0, 1.0, v_DistanceFromCenter * 2.0);
        vec3 explosionColor = lavaPalette(v_ExplosionPhase * 0.5);
        gl_FragColor.rgb = mix(
            gl_FragColor.rgb,
            explosionColor * explosionGlow,
            explosionStrength * 0.6
        );
        
        // Add explosion distortion
        float distortion = sin(v_DistanceFromCenter * 25.0 - u_Time * 6.0) * 0.5 + 0.5;
        gl_FragColor.rgb *= 1.0 + distortion * explosionStrength * 0.4;
    }
    
    // Ensure proper alpha handling
    if(gl_FragColor.a < 0.01) discard;
} 