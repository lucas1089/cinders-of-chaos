uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform vec2 u_Resolution;
uniform float u_Time;

// Matrix code parameters
float codeSpeed = 1.2;          // Speed of code falling
float codeDensity = 15.0;       // Density of code patterns
float dataOpacity = 0.9;        // Overall opacity of effect
float dataGridSize = 4.0;       // Size of data cells
float pulseRate = 0.8;          // Rate of data pulse

// Hash function for pseudo-random values
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Generate matrix code patterns
float matrixCode(vec2 uv, float time) {
    // Create falling code effect
    float yOffset = time * codeSpeed;
    
    // Column-based animation
    float column = floor(uv.x * codeDensity);
    float columnOffset = hash(vec2(column, 0.0)) * 10.0;
    
    // Adjust y position with column-specific speed
    float adjustedY = fract(uv.y + yOffset * (0.5 + hash(vec2(column, 1.0)) * 0.5) + columnOffset);
    
    // Create character cells
    float row = floor(adjustedY * codeDensity * 2.0);
    vec2 cellId = vec2(column, row);
    
    // Use hash to determine which cells show characters
    float charBrightness = hash(cellId + floor(time * 0.5));
    float charVisible = step(0.5, charBrightness);
    
    // Create character blinking effect
    float blink = hash(cellId + floor(time * 8.0));
    charVisible *= (blink > 0.95) ? 0.0 : 1.0;
    
    // Create character pulse effect
    float pulse = pow(sin(hash(cellId) * 10.0 + time * 2.0) * 0.5 + 0.5, 2.0);
    
    // Calculate final character brightness with falloff based on screen position
    float codeBrightness = charVisible * charBrightness * pulse;
    
    // Brighten lead characters (droplets)
    float isLeadChar = step(0.97, hash(vec2(column, 3.0)));
    float leadRow = fract(yOffset * (0.5 + hash(vec2(column, 1.0)) * 0.5) + columnOffset);
    float leadDistance = abs(adjustedY - leadRow);
    float leadEffect = isLeadChar * smoothstep(0.1, 0.0, leadDistance) * 2.0;
    
    return codeBrightness + leadEffect;
}

// Create data grid pattern
float dataGrid(vec2 uv, float time) {
    // Scale up coordinates to desired grid cell size
    vec2 cell = fract(uv * dataGridSize);
    
    // Create grid lines with animated pulse
    float gridLine = step(0.9, cell.x) + step(0.9, cell.y);
    
    // Add pulsing to grid cells
    vec2 cellCenter = floor(uv * dataGridSize) + vec2(0.5);
    float cellId = hash(cellCenter);
    float cellActive = step(0.6, cellId);
    
    // Create data pulse
    float dataPulse = sin(time * pulseRate + cellId * 10.0) * 0.5 + 0.5;
    float cellPulse = cellActive * dataPulse * 0.3;
    
    // Create data flow effect along grid lines
    float flowEffect = step(0.95, cell.y) * sin(uv.x * 20.0 + time * 5.0) * 0.5 + 0.5;
    flowEffect += step(0.95, cell.x) * sin(uv.y * 20.0 - time * 5.0) * 0.5 + 0.5;
    
    // Combine effects
    return gridLine * 0.5 + cellPulse + flowEffect * 0.3;
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
    
    // Get distance and angle from vertex shader
    float distFromCenter = v_TexCoord3.x;
    float angle = v_TexCoord3.y;
    
    // Create time variables
    float time = u_Time;
    
    // Generate matrix code and data grid patterns
    vec2 offsetCoord = v_TexCoord * 2.0; // Scale up for more detail
    float code = matrixCode(offsetCoord, time);
    float grid = dataGrid(offsetCoord, time);
    
    // Create matrix color - green for classic matrix look
    vec3 matrixColor = vec3(0.0, 1.0, 0.4);
    
    // Create subtle color variation based on position
    float colorShift = sin(angle * 2.0 + time) * 0.2 + 0.8;
    matrixColor.b += colorShift * 0.3; // Add some cyan variation
    
    // Combine code and grid effects
    float matrixEffect = code * 0.7 + grid * 0.6;
    
    // Add hex/binary pattern overlay
    float hexPattern = 0.0;
    for (int i = 0; i < 3; i++) {
        float scale = float(i) * 5.0 + 10.0;
        float scrollSpeed = 0.2 + float(i) * 0.1;
        
        vec2 hexCoord = offsetCoord * scale;
        hexCoord.y += time * scrollSpeed * (mod(float(i), 2.0) * 2.0 - 1.0); // Alternate directions
        
        vec2 hexId = floor(hexCoord);
        float hexHash = hash(hexId + floor(time * 0.5));
        float isData = step(0.7, hexHash);
        
        hexPattern += isData * 0.1 * (0.6 + 0.4 * sin(time * 2.0 + float(i)));
    }
    
    // Add digital circuit pattern
    float circuitPattern = 0.0;
    
    // Horizontal lines
    for (float i = 0.0; i < 3.0; i++) {
        float yPos = hash(vec2(i, 0.0)) * 2.0 - 1.0;
        float thickness = 0.02 + hash(vec2(i, 1.0)) * 0.02;
        float line = smoothstep(thickness, 0.0, abs(offsetCoord.y - yPos));
        
        // Add nodes along the line
        for (float j = 0.0; j < 4.0; j++) {
            float xPos = hash(vec2(i, j + 10.0)) * 2.0 - 1.0;
            float nodeSize = 0.03 + hash(vec2(i, j + 20.0)) * 0.02;
            float node = smoothstep(nodeSize, 0.0, length(offsetCoord - vec2(xPos, yPos)));
            
            // Add pulsing to nodes
            float nodePulse = 0.5 + 0.5 * sin(time * 2.0 + i * 1.5 + j * 2.7);
            circuitPattern += node * nodePulse * 0.3;
        }
        
        circuitPattern += line * 0.15;
    }
    
    // Add digital data pulses that move along the circuit lines
    for (float i = 0.0; i < 5.0; i++) {
        float lineIdx = floor(i / 2.0);
        float yPos = hash(vec2(lineIdx, 0.0)) * 2.0 - 1.0;
        
        float pulsePos = fract(time * (0.2 + hash(vec2(i, 30.0)) * 0.3) + hash(vec2(i, 31.0)));
        float xPos = pulsePos * 2.0 - 1.0;
        
        float pulseSize = 0.04;
        float pulse = smoothstep(pulseSize, 0.0, length(offsetCoord - vec2(xPos, yPos)));
        circuitPattern += pulse * 0.4;
    }
    
    // Combine all matrix effects
    matrixEffect += hexPattern + circuitPattern;
    
    // Create edge data flow effect
    float edgeFlow = smoothstep(0.8, 1.0, distFromCenter);
    float edgeData = sin(angle * 20.0 + time * 3.0) * 0.5 + 0.5;
    edgeData *= edgeFlow;
    matrixEffect += edgeData * 0.4;
    
    // Add data scan effect - horizontal scan line
    float scanPos = fract(time * 0.2) * 2.0 - 1.0;
    float scan = smoothstep(0.05, 0.0, abs(offsetCoord.y - scanPos));
    matrixEffect += scan * 0.3;
    
    // Generate final matrix data color
    vec3 dataEffect = matrixColor * matrixEffect;
    
    // Create ambient matrix glow
    vec3 ambientGlow = matrixColor * 0.1 * (1.0 - distFromCenter);
    
    // Add bright highlights for cyberpunk feel
    vec3 highlights = vec3(0.9, 1.0, 1.0) * pow(matrixEffect, 3.0) * 2.0;
    
    // Calculate final effect color
    vec3 finalEffect = dataEffect + ambientGlow + highlights;
    
    // Apply dark area where matrix code should show through
    vec3 darkBase = baseColor.rgb * 0.1;
    
    // Mix with original texture - partially transparent data overlay
    float effectFalloff = 0.15 + (1.0 - distFromCenter) * 0.2; // Stronger in center
    vec3 matrixOverlay = mix(darkBase, finalEffect, matrixEffect);
    
    baseColor.rgb = mix(baseColor.rgb, matrixOverlay, dataOpacity * effectFalloff);
    
    // Set output color
    gl_FragColor = baseColor;
} 