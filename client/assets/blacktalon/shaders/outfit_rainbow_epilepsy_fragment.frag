uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Epilepsy Rainbow parameters
float rainbowIntensity = 0.9; // Extremely strong rainbow effect
float dustIntensity = 0.4; // Intensity of pogo dust effect
float flashIntensity = 0.3; // Intensity of epileptic flashes

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
    
    // Get time and bounce phase from vertex shader
    float currentTime = v_TexCoord3.x;
    float bouncePhase = v_TexCoord3.y;
    
    // Extremely fast rainbow cycling with multiple colors at once
    // Create a striped pattern with rapid color changes
    float colorStripesX = fract(v_TexCoord.x * 5.0 + currentTime * 2.5) * 6.0;
    float colorStripesY = fract(v_TexCoord.y * 5.0 - currentTime * 3.5) * 6.0;
    
    // X direction rainbow
    vec3 rainbowX;
    float xHue = fract(colorStripesX);
    float xi = floor(xHue * 6.0);
    float xf = xHue * 6.0 - xi;
    float xp = 0.0;
    float xq = 1.0 - xf;
    float xt = xf;
    
    if(xi == 0.0) rainbowX = vec3(1.0, xt, xp);
    else if(xi == 1.0) rainbowX = vec3(xq, 1.0, xp);
    else if(xi == 2.0) rainbowX = vec3(xp, 1.0, xt);
    else if(xi == 3.0) rainbowX = vec3(xp, xq, 1.0);
    else if(xi == 4.0) rainbowX = vec3(xt, xp, 1.0);
    else rainbowX = vec3(1.0, xp, xq);
    
    // Y direction rainbow
    vec3 rainbowY;
    float yHue = fract(colorStripesY);
    float yi = floor(yHue * 6.0);
    float yf = yHue * 6.0 - yi;
    float yp = 0.0;
    float yq = 1.0 - yf;
    float yt = yf;
    
    if(yi == 0.0) rainbowY = vec3(1.0, yt, yp);
    else if(yi == 1.0) rainbowY = vec3(yq, 1.0, yp);
    else if(yi == 2.0) rainbowY = vec3(yp, 1.0, yt);
    else if(yi == 3.0) rainbowY = vec3(yp, yq, 1.0);
    else if(yi == 4.0) rainbowY = vec3(yt, yp, 1.0);
    else rainbowY = vec3(1.0, yp, yq);
    
    // Time-based global rainbow
    vec3 rainbowTime;
    float tHue = fract(currentTime * 0.3);
    float ti = floor(tHue * 6.0);
    float tf = tHue * 6.0 - ti;
    float tp = 0.0;
    float tq = 1.0 - tf;
    float tt = tf;
    
    if(ti == 0.0) rainbowTime = vec3(1.0, tt, tp);
    else if(ti == 1.0) rainbowTime = vec3(tq, 1.0, tp);
    else if(ti == 2.0) rainbowTime = vec3(tp, 1.0, tt);
    else if(ti == 3.0) rainbowTime = vec3(tp, tq, 1.0);
    else if(ti == 4.0) rainbowTime = vec3(tt, tp, 1.0);
    else rainbowTime = vec3(1.0, tp, tq);
    
    // Mix all three rainbow effects for maximum epilepsy
    vec3 epilepsyRainbow = rainbowX * 0.4 + rainbowY * 0.4 + rainbowTime * 0.2;
    epilepsyRainbow *= 1.2; // Boost brightness
    
    // Apply rainbow with high intensity
    baseColor.rgb = mix(baseColor.rgb, epilepsyRainbow, rainbowIntensity);
    
    // Add dust effect when at bottom of bounce (pogo stick effect)
    if(bouncePhase < 0.15 || bouncePhase > 0.85) {
        // Only at the bottom of the sprite
        if(v_TexCoord.y > 0.7) {
            // Calculate dust amount
            float dustPhase;
            if(bouncePhase < 0.15) {
                dustPhase = 1.0 - (bouncePhase / 0.15); // 1 to 0 as we leave the ground
            } else {
                dustPhase = (bouncePhase - 0.85) / 0.15; // 0 to 1 as we hit the ground
            }
            
            // Create dust pattern
            float dustX = v_TexCoord.x * 20.0;
            float dustY = v_TexCoord.y * 10.0;
            float dust = sin(dustX) * sin(dustY) * 0.5 + 0.5;
            dust = smoothstep(0.4, 0.6, dust);
            
            // Apply dust effect - pick a color from our rainbow for the dust
            baseColor.rgb = mix(baseColor.rgb, epilepsyRainbow * 0.7, dust * dustPhase * dustIntensity);
        }
    }
    
    // Add epileptic flashing
    float flashRate = 15.0; // Very rapid flashing
    float flashPhase = fract(currentTime * flashRate * 0.1);
    if(flashPhase < 0.5) {
        // Rapid white flash
        baseColor.rgb += vec3(flashPhase * flashIntensity);
    }
    
    // Random color inversions for extra epilepsy
    float invertRate = 8.0;
    float invertPhase = fract(currentTime * invertRate * 0.1);
    if(invertPhase < 0.2) {
        // Invert colors briefly
        baseColor.rgb = mix(baseColor.rgb, 1.0 - baseColor.rgb, invertPhase * 5.0 * flashIntensity);
    }
    
    // Set output color
    gl_FragColor = baseColor;
} 