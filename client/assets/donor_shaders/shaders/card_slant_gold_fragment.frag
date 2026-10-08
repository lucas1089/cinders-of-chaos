// Card da Oferta do Dia: PARALELOGRAMO desenhado por inteiro aqui, com halo.
//
// Diferente de um veu por cima de um card retangular, este shader e a forma
// toda: halo externo, contorno, miolo e o vazio de fora. O que cai fora do halo
// e DESCARTADO, entao os cantos ficam transparentes e a arte do banner aparece
// atraves deles -- e isso que tira o card da cara de retangulo colado por cima
// da imagem.
//
// Por isso quem usa este shader precisa apagar o fundo e a borda do proprio
// widget (clearBackgroundGradient + setBorderWidth 0): sao retangulos e
// apareceriam por baixo, denunciando a forma real.
//
// A forma e INSETADA por GLOW_PAD: essa folga entre a forma e a borda do widget
// e onde o halo mora. Sem ela nao ha para onde o brilho vazar.
//
// A cor vem do u_Color (setBackgroundColor do widget), como no rarity_glow --
// o mesmo shader serve dourado, vermelho ou o que a loja pedir.
//
// O ALPHA do u_Color e usado como CANAL DE ESTADO (hover/anel), nao como
// opacidade: shader de FUNDO nao tem setBackgroundShaderVar -- so o de imagem
// tem -- entao u_Color e o unico caminho de parametro que existe. Alpha cheio
// (255) = aceso; abaixo de ~240 = repouso. Ver PROMO_TINT no store.lua.
//
// Foi esse o motivo de nao clarear o tom no hover: clarear o tint lava o miolo
// escuro e o card fica com cara de desabilitado. Aceso, o que sobe e o
// CONTORNO e o HALO -- o miolo quase nao muda, e ai o realce le como luz.
// donor client MMORPG

precision mediump float;

uniform vec4 u_Color;
uniform float u_Time;
varying vec2 v_TexCoord;

// Inclinacao: fracao da largura que o topo anda pra direita em relacao a base.
// 0.0 = retangulo. Acima de ~0.30 o miolo util fica estreito demais pro conteudo.
const float SKEW = 0.16;
// Folga reservada pro halo, em fracao do widget. E tambem o alcance dele.
const float GLOW_PAD = 0.075;
// Espessura do contorno.
const float LINE = 0.020;
// Ate onde o brilho do contorno sobe pra DENTRO do card.
const float INNER_BAND = 0.26;

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
    vec3 tint = u_Color.rgb;
    // Estado, nao opacidade -- ver a nota do cabecalho.
    float hot = smoothstep(0.94, 1.0, u_Color.a);

    // Desfaz a inclinacao: no espaco `sx` o paralelogramo vira um retangulo, e a
    // conta de distancia pra borda volta a ser trivial.
    // uv.y = 0 e o TOPO, entao (1 - uv.y) empurra o topo pra direita.
    float shift = SKEW * (1.0 - uv.y);
    float sx = uv.x - shift;
    float w = 1.0 - SKEW;

    // Distancia pra borda da forma: POSITIVA dentro, NEGATIVA fora. O inset de
    // GLOW_PAD e o que abre espaco pro halo entre a forma e a borda do widget.
    float dx = min(sx - GLOW_PAD, (w - GLOW_PAD) - sx);
    float dy = min(uv.y - GLOW_PAD, (1.0 - GLOW_PAD) - uv.y);
    float d = min(dx, dy);

    // Respiro do halo, pra faixa nao ficar estatica.
    float breath = 0.80 + 0.20 * sin(t * 1.3);

    if (d < 0.0) {
        // ---- FORA da forma: halo ----
        float out_ = -d;
        if (out_ > GLOW_PAD) discard;             // alem do halo nao existe nada
        float fall = 1.0 - (out_ / GLOW_PAD);
        // Aceso o halo quase dobra de forca: e o sinal de hover mais visivel que
        // existe aqui, porque acontece FORA do card, contra a arte do banner.
        float a = pow(fall, 2.2) * (0.70 + 0.60 * hot) * breath;
        if (a < 0.004) discard;
        // Halo mais claro que o corpo: le como luz, nao como borda grossa.
        gl_FragColor = vec4(clamp(tint * (1.15 + 0.30 * hot), 0.0, 1.0), a);
        return;
    }

    // ---- DENTRO da forma ----
    float line = 1.0 - smoothstep(0.0, LINE, d);
    float inner = pow(1.0 - smoothstep(0.0, INNER_BAND, d), 1.7);

    // Metal liquido escorrendo devagar, so pro miolo nao ficar chapado. O realce
    // ridged (1 - abs(2x-1)) acende as CRISTAS: le como veio, nao como fumaca.
    vec2 p = uv * 3.0 + vec2(0.0, t * 0.10);
    p += 0.45 * vec2(fbm(p * 0.7), fbm(p * 0.7 + 5.0));
    float vein = 1.0 - abs(2.0 * fbm(p) - 1.0);
    vein = smoothstep(0.58, 0.95, vein);

    // Varredura diagonal de luz, com intervalo apagado entre passadas pra nao
    // virar estrobo. Usa sx pra correr no eixo do card, nao no da tela.
    float sweepPos = mod(t * 0.30, 3.0) - 0.6;
    float sweep = exp(-pow(((sx / w + uv.y) * 0.5 - sweepPos) * 4.5, 2.0));

    // Miolo bem escuro: sprite, nome e preco desenham por cima disto. Aceso ele
    // sobe pouquissimo de proposito -- clarear o miolo lava o card e ele fica
    // com cara de desabilitado, que era o problema da primeira tentativa.
    vec3 col = mix(vec3(0.06, 0.02, 0.02), tint * 0.50, inner * (0.60 + 0.12 * hot));
    col += tint * vein * 0.22 * (0.35 + inner);
    col += tint * sweep * (0.28 + 0.16 * hot);
    // O fio da borda manda na cor, e e ele que ACENDE no hover.
    col = mix(col, tint * (1.30 + 0.55 * hot), line);

    float alpha = 0.82 + 0.18 * line;

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), clamp(alpha, 0.0, 1.0));
}
