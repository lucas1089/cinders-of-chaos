// Oferta do Dia -- veu de ouro liquido por cima do card INTEIRO.
//
// Usado como background-shader de um overlay que cobre o card (game_store). A
// cor vem do u_Color, ou seja do setBackgroundColor do widget, entao o mesmo
// shader serve pra qualquer tom; a loja passa dourado.
//
// Herda do outfit_void_ext a ideia das veias: fbm com o dominio deformado por
// outro fbm, que da um escoamento organico em vez de onda regular. O que muda e
// a intencao -- ali o efeito COME a silhueta, aqui ele tem de MOLDURAR conteudo
// que precisa continuar legivel. Por isso tudo e pesado pela distancia da borda:
// forte na moldura, quase nada no meio, onde ficam a sprite e o preco.
//
// A textura sob o shader e ignorada de proposito (o drawBackground manda um
// panel_map qualquer): tudo aqui e matematica de UV, entao nao depende de asset.
// donor client MMORPG

precision mediump float;

uniform vec4 u_Color;
uniform float u_Time;
varying vec2 v_TexCoord;

// Largura da faixa (em UV) em que o ouro aparece, medida da borda pra dentro.
const float FRAME_BAND = 0.34;
// Espessura do fio aceso encostado na borda.
const float RIM_BAND = 0.035;
// Velocidade do escoamento das veias e da varredura de brilho.
const float FLOW_SPEED = 0.13;
const float SWEEP_SPEED = 0.32;

vec2 hash2(vec2 p)
{
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(i).x;
    float b = hash2(i + vec2(1.0, 0.0)).x;
    float c = hash2(i + vec2(0.0, 1.0)).x;
    float d = hash2(i + vec2(1.0, 1.0)).x;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Tres octaves bastam: isto roda em ate ~10 cards por pagina, e a faixa util do
// efeito e estreita.
float fbm(vec2 p)
{
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { s += a * vnoise(p); p *= 2.0; a *= 0.5; }
    return s;
}

void main()
{
    vec2 uv = v_TexCoord;
    float t = u_Time;

    // Distancia pra borda mais perto: 0 na moldura, ~0.5 no centro.
    float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));

    // Peso da moldura. pow puxa o efeito ainda mais pra borda, deixando o miolo
    // do card limpo pra sprite e preco.
    float frame = 1.0 - smoothstep(0.0, FRAME_BAND, d);
    frame = pow(frame, 1.6);

    // Fio aceso na borda: e ele que da o contorno de metal.
    float rim = 1.0 - smoothstep(0.0, RIM_BAND, d);

    // Veias de ouro liquido: fbm com dominio deformado por outro fbm. O eixo Y
    // anda com o tempo, entao o metal parece escorrer devagar.
    vec2 p = uv * 3.4;
    p += 0.55 * vec2(fbm(p * 0.6 + vec2(t * FLOW_SPEED, 0.0)),
                     fbm(p * 0.6 + vec2(0.0, t * FLOW_SPEED * 0.7)));
    float veinRaw = fbm(p);
    // ridged: acende as CRISTAS em vez do borrao todo -- e o que faz parecer
    // veio de metal e nao fumaca.
    float vein = 1.0 - abs(2.0 * veinRaw - 1.0);
    float veinBody = smoothstep(0.55, 0.95, vein);

    // Varredura diagonal de luz, como reflexo passando por metal polido. O mod
    // com periodo maior que o alcance deixa um intervalo apagado entre passadas,
    // senao viraria estrobo.
    float sweepPos = mod(t * SWEEP_SPEED, 3.2) - 0.6;
    float sweep = exp(-pow(((uv.x + uv.y) * 0.5 - sweepPos) * 4.2, 2.0));

    // Respiro lento, pra faixa nao ficar estatica quando nada mais se move.
    float breath = 0.86 + 0.14 * sin(t * 1.15);

    float alpha = 0.0;
    alpha += frame * (0.30 + 0.34 * veinBody);
    alpha += rim * 0.50;
    alpha += sweep * (0.16 + 0.20 * frame);   // no meio a varredura e discreta
    alpha *= breath;

    if (alpha < 0.004) discard;

    // Clareia onde a veia e a varredura batem, pra leitura de ouro polido em vez
    // de tinta chapada.
    vec3 col = u_Color.rgb * (0.90 + 0.55 * veinBody + 0.45 * sweep + 0.30 * rim);

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(alpha, 0.0, 1.0) * u_Color.a);
}
