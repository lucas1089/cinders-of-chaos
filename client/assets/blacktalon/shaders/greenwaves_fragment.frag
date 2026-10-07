uniform float u_Time;
uniform vec2 u_Resolution;

void main()
{
    vec2 uv = gl_FragCoord.xy / u_Resolution;
    
    // Movimento lento e suave em loop
    float slowTime = u_Time * 0.2; // Reduz a velocidade da animação
    float waveX = sin(uv.y * 5.0 + slowTime) * 0.1; // Ondas horizontais suaves
    float waveY = cos(uv.x * 5.0 + slowTime) * 0.1; // Ondas verticais suaves

    // Combina as ondas para criar um efeito tranquilo e contínuo
    float lines = sin((uv.x + waveX + waveY) * 200.0) * 0.5 + 0.5;
    
    // Define as cores: verde claro e verde similar
    vec3 greenLight = vec3(0.0, 1.0, 0.0); // Verde claro
    vec3 greenSimilar = vec3(0.0, 0.8, 0.0); // Verde similar (um pouco mais escuro)

    // Interpola entre verde claro e verde similar com base nas linhas
    vec3 color = mix(greenSimilar, greenLight, lines);

    gl_FragColor = vec4(color, 0.5); // Mantém a transparência
}