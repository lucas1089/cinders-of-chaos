// pt-BR texts of the community windows (admin panel, boss spawns, survey, nemesis, referral, community goal, chronicle, mentors, patch notes, drop feed, credits, streamer and cinema
// mode, performance, screenshots, Customise Character). Merged into LocStrings.PtBr by its static constructor (indexer, so a key another file also has is not an error).
// Keys are the English text.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocCommunity
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            // admin panel
            { "{0}d ago", "há {0}d" }, { "missing required field", "campo obrigatório faltando" }, { "All actions", "Todas as ações" }, { "Admin Panel", "Painel de administração" },
            { "  (dangerous)", "  (perigosa)" }, { "Select an action", "Escolha uma ação" }, { "filter actions", "filtrar ações" }, { "dangerous", "perigosa" },
            { "No action matches.", "Nenhuma ação combina." }, { "Click again to confirm", "Clique de novo para confirmar" }, { "Run", "Executar" }, { "Results", "Resultados" },
            // boss spawns
            { "Alive ({0})", "Vivo ({0})" }, { "Alive", "Vivo" }, { "Respawns in {0}", "Volta em {0}" }, { "Respawn due", "Hora de voltar" }, { "In {0}", "Em {0}" }, { "Starting", "Começando" },
            { "Random", "Aleatório" }, { "On demand", "Sob demanda" }, { "Your cooldown {0}", "Sua espera {0}" }, { "Not seen yet", "Ainda não visto" }, { "Slain {0}", "Morto {0}" },
            { " by {0}", " por {0}" }, { "Pocket: level {0}+", "Bolso: nível {0}+" }, { "Last kill: {0}", "Última morte: {0}" }, { " ({0} kills)", " ({0} mortes)" }, { "Position: {0}", "Posição: {0}" },
            { "Pocket: a private copy of this boss, open any time, alone or with your party (each member spends a charge).", "Bolso: uma cópia particular deste chefe, aberta a qualquer hora, sozinho ou com seu grupo (cada membro gasta uma carga)." },
            { "Less experience and loot than the scheduled fight; the boss passive point counts the same.", "Menos experiência e loot que a luta marcada; o ponto passivo do chefe conta igual." },
            { "Charges left: {0} (daily {1}, bonus {2}). New daily charges in {3}.", "Cargas restantes: {0} (diárias {1}, bônus {2}). Novas cargas diárias em {3}." },
            { "Needs level {0}.", "Precisa do nível {0}." }, { "You are in a pocket now.", "Você está em um bolso agora." }, { "Pocket {0}/{1}", "Bolso {0}/{1}" }, { "of", "de" }, { " - {0} alive", " - {0} vivos" },
            { "Boss Spawns", "Chefes" }, { "Updated just now", "Atualizado agora" }, { "Updated {0}", "Atualizado {0}" }, { "boss or place", "chefe ou lugar" }, { "No boss matches.", "Nenhum chefe combina." },
            { "No bosses listed.", "Nenhum chefe na lista." }, { "Hide", "Ocultar" },
            // survey
            { "Answer at least one question, or press Skip.", "Responda ao menos uma pergunta, ou aperte Pular." }, { "A few questions", "Algumas perguntas" },
            { "Your answers help us make the game better. This takes a minute.", "Suas respostas nos ajudam a melhorar o jogo. Leva um minuto." },
            { "Where did you hear about the game?", "Onde você ouviu falar do jogo?" }, { "What confused you so far?", "O que confundiu você até agora?" }, { "optional", "opcional" },
            { "How fun is it? (1 to 5)", "Quão divertido é? (1 a 5)" }, { "Would you recommend it?", "Você recomendaria?" }, { "Send your answers", "Enviar suas respostas" }, { "Skip", "Pular" },
            { "Discord", "Discord" }, { "A forum", "Um fórum" }, { "A server list", "Uma lista de servidores" }, { "YouTube", "YouTube" }, { "TikTok, Reels or Shorts", "TikTok, Reels ou Shorts" },
            { "A streamer", "Um streamer" }, { "A friend", "Um amigo" }, { "A web search", "Uma busca na web" }, { "Somewhere else", "Em outro lugar" },
            // nemesis
            { "{0} min ago", "há {0} min" }, { "{0} h ago", "há {0} h" }, { "{0} day ago", "há {0} dia" }, { "{0} days ago", "há {0} dias" },
            { "A {0} that killed you once", "Um {0} que matou você uma vez" }, { "A {0} that killed you twice", "Um {0} que matou você duas vezes" },
            { "A {0} that killed you three times", "Um {0} que matou você três vezes" }, { "A {0} that killed you {1} times", "Um {0} que matou você {1} vezes" },
            { "No Nemesis hunts you", "Nenhum Nêmesis caça você" },
            { "When a monster kills you (level 50 or more), it may become your Nemesis. It returns while you hunt its kind. Slay it for a trophy and the title Avenger of Self.", "Quando um monstro mata você (nível 50 ou mais), ele pode virar seu Nêmesis. Ele volta enquanto você caça a espécie dele. Derrote-o por um troféu e pelo título Vingador de Si." },
            { "Last seen", "Visto por último" }, { "Fades in", "Some em" }, { "Traits", "Traços" },
            { "Nemeses avenged: {0}   |   Nemeses of others slain: {1}", "Nêmesis vingados: {0}   |   Nêmesis de outros derrotados: {1}" },
            { "{0} day", "{0} dia" }, { "{0} days", "{0} dias" }, { "{0} h", "{0} h" }, { "under an hour", "menos de uma hora" }, { "Nemesis", "Nêmesis" },
            // referral
            { "{0} day left", "falta {0} dia" }, { "{0} days left", "faltam {0} dias" }, { "{0} hour left", "falta {0} hora" }, { "{0} hours left", "faltam {0} horas" },
            { "{0} and the title {1}", "{0} e o título {1}" }, { "Your friend gets: {0}.", "Seu amigo ganha: {0}." }, { "level {0}: {1}", "nível {0}: {1}" },
            { "You get, when your friend's first character reaches {0}.", "Você ganha quando o primeiro personagem do seu amigo chegar a {0}." },
            { "{0} friends: {1}{2}", "{0} amigos: {1}{2}" }, { "(yours)", "(seu)" },
            { "And with friends at level {0} ({1} so far): {2}.", "E com amigos no nível {0} ({1} até agora): {2}." }, { "You were referred by {0}.", "Você foi indicado por {0}." },
            { " Your welcome gift was given.", " Seu presente de boas-vindas foi entregue." }, { " Your welcome gift comes at your next login.", " Seu presente de boas-vindas chega no próximo login." },
            { "The code from your account creation was not accepted: {0} You can enter another one ({1}).", "O código da criação da sua conta não foi aceito: {0} Você pode digitar outro ({1})." },
            { "Got a code from a friend? Enter it here ({0}).", "Recebeu um código de um amigo? Digite aqui ({0})." },
            { "waiting", "aguardando" }, { "rewarded", "recompensado" }, { "no reward", "sem recompensa" },
            { "This month: {0} / {1} new friends, {2} / {3} rewards.   Chaos Coins earned: {4}", "Neste mês: {0} / {1} novos amigos, {2} / {3} recompensas.   Chaos Coins ganhas: {4}" },
            { "Type the code first.", "Digite o código primeiro." }, { "Referral", "Indicação" }, { "Your code", "Seu código" }, { "The referral program is off.", "O programa de indicação está desligado." },
            { "Copy code", "Copiar código" }, { "Code copied.", "Código copiado." }, { "Share it, or the link {0}", "Compartilhe, ou o link {0}" },
            { "Share it: a friend enters it when creating an account on the website, or in this window in the first week.", "Compartilhe: um amigo digita o código ao criar a conta no site, ou nesta janela na primeira semana." },
            { "Friend's code", "Código do amigo" }, { "code", "código" }, { "Use code", "Usar código" }, { "Referred friends", "Amigos indicados" }, { "Referred friends ({0})", "Amigos indicados ({0})" },
            { "Nobody has joined with your code yet.", "Ninguém entrou com seu código ainda." }, { "Lv {0}: {1}", "Nv {0}: {1}" }, { "Level {0}, joined {1}", "Nível {0}, entrou em {1}" },
            // community goal
            { "Active: {0} left", "Ativo: falta {0}" }, { "Reached at {0}%", "Alcançado em {0}%" }, { "At {0}%", "Em {0}%" },
            { "{0} ({1}%)\n{2} for everyone online, {3} hours.", "{0} ({1}%)\n{2} para todos online, {3} horas." }, { " (rank {0})", " (posição {0})" }, { "{0} points{1}", "{0} pontos{1}" },
            { "Today: {0} / {1}", "Hoje: {0} / {1}" }, { "Top {0}: the title {1}.", "Top {0}: o título {1}." }, { "{0} points: {1}{2}", "{0} pontos: {1}{2}" }, { "a reward", "uma recompensa" }, { "(earned)", "(ganho)" },
            { "No world modifier this week.", "Nenhum modificador de mundo nesta semana." }, { "This week ({0} left){1}", "Nesta semana (falta {0}){1}" }, { ", set by the staff", ", definido pela equipe" },
            { "Enter an amount of gold.", "Digite uma quantia de ouro." }, { "At least {0} gold.", "No mínimo {0} de ouro." }, { "The Brazier takes no more from you today.", "O Braseiro não aceita mais nada de você hoje." },
            { "You do not have that much gold.", "Você não tem tanto ouro." }, { "Stand next to the Great Brazier in the temple.", "Fique ao lado do Grande Braseiro no templo." },
            { "Give {0} gold for {1} points.", "Dar {0} de ouro por {1} pontos." }, { "Community", "Comunidade" }, { "Stages", "Etapas" }, { "Your part", "Sua parte" }, { "Top contributors", "Maiores contribuintes" },
            { "Nobody yet.", "Ninguém ainda." }, { "You carry {0} gold (backpack and bank). The Brazier takes up to {1} more from you today.", "Você carrega {0} de ouro (mochila e banco). O Braseiro aceita até mais {1} de você hoje." },
            { "Gold to give", "Ouro a dar" }, { "150k, 1.5m, 25,000", "150k, 1.5m, 25.000" }, { "Give the gold to the Brazier", "Dar o ouro ao Braseiro" }, { "Give", "Dar" }, { "Goal", "Meta" }, { "Brazier", "Braseiro" },
            // chronicle
            { "Written on {0}", "Escrito em {0}" }, { "Written", "Escrito" }, { "Open: {0}% written", "Aberto: {0}% escrito" }, { "Not yet told", "Ainda não contado" },
            { "a hero who keeps their name", "um herói que guarda seu nome" }, { "level {0} {1}, {2}", "nível {0} {1}, {2}" }, { "adventurer", "aventureiro" }, { "Ashen Chronicle", "Crônica das Cinzas" },
            { "Season {0}", "Temporada {0}" }, { "The Chronicle has no chapter yet.", "A Crônica ainda não tem capítulo." }, { "Chapters", "Capítulos" }, { "Shown", "Mostrado" }, { "Read", "Ler" },
            { "The way is not on the map yet: the staff is placing it.", "O caminho ainda não está no mapa: a equipe está colocando." }, { "No season is written down yet.", "Nenhuma temporada foi registrada ainda." },
            { "Capital Memorial", "Memorial da Capital" }, { "Section", "Seção" }, { "Your fall waits for an answer", "Sua queda espera uma resposta" }, { "Show me on the Memorial", "Mostrar-me no Memorial" },
            { "The Capital Memorial remembers the realm's firsts, its records and the heroes who fell in Hardcore. Choose what it may say about you.", "O Memorial da Capital lembra os primeiros do reino, seus recordes e os heróis que caíram no Hardcore. Escolha o que ele pode dizer sobre você." },
            { "Show my name on records", "Mostrar meu nome nos recordes" }, { "Show me among the fallen", "Mostrar-me entre os caídos" }, { "Save your choice", "Salvar sua escolha" }, { "Choice sent.", "Escolha enviada." },
            { "Nothing is remembered here yet.", "Nada é lembrado aqui ainda." }, { "Memorial", "Memorial" }, { "Chronicle", "Crônica" }, { "Record", "Registro" },
            { "Your choice", "Sua escolha" }, { "Realm firsts", "Primeiros do reino" }, { "Records", "Recordes" }, { "The fallen", "Os caídos" },
            // mentors
            { "expired", "expirado" }, { "{0}s left", "falta {0}s" }, { "{0} min left", "faltam {0} min" }, { "The mentor system is off.", "O sistema de mentores está desligado." },
            { "You have a mentor: see My mentor.", "Você tem um mentor: veja Meu mentor." },
            { "New characters (up to level {0}, account up to {1} days old) can pick a mentor. Hunting together in a party gives you +{2}% experience and {3}% less damage from monsters while your mentor is not far above the monsters. You graduate at level {4}.", "Personagens novos (até o nível {0}, conta com até {1} dias) podem escolher um mentor. Caçar junto em grupo dá +{2}% de experiência e {3}% menos dano dos monstros enquanto seu mentor não está muito acima dos monstros. Você se forma no nível {4}." },
            { "{0} place free", "{0} vaga livre" }, { "{0} places free", "{0} vagas livres" }, { "Your referrer mentors as {0}.", "Quem indicou você é mentor como {0}." },
            { "{0} (Lv {1} {2}) invites you - {3}", "{0} (Nv {1} {2}) convida você - {3}" }, { "marks paid", "marcas pagas" }, { "no marks", "sem marcas" }, { "month cap", "limite do mês" }, { "before the link", "antes do vínculo" },
            { "Thank your mentor: you can become one yourself one day.", "Agradeça ao seu mentor: um dia você pode ser um." }, { "You graduated.", "Você se formou." },
            { "Pick one in Find a mentor, or accept an invitation.", "Escolha um em Achar um mentor, ou aceite um convite." }, { "You have no mentor.", "Você não tem mentor." },
            { "online", "online" }, { "offline", "offline" }, { "chosen from the list", "escolhido da lista" }, { "by invitation", "por convite" }, { "your referrer", "quem indicou você" },
            { "Mentor since {0} ({1}). Hunted together: {2}.", "Mentor desde {0} ({1}). Caçaram juntos: {2}." },
            { "Mentors: an account with a level {0} character, {1} hours of play and {2} days of age. Up to {3} apprentices. You earn Mentor Marks from their milestones (after {4} minutes hunting together) and 1 mark per {5} minutes of hunting together ({6} a day, {7} a month in all). Marks buy titles, cosmetics and supplies, never power.", "Mentores: uma conta com um personagem de nível {0}, {1} horas de jogo e {2} dias de idade. Até {3} aprendizes. Você ganha Marcas de Mentor pelos marcos deles (após {4} minutos caçando juntos) e 1 marca a cada {5} minutos caçando juntos ({6} por dia, {7} por mês no total). As marcas compram títulos, cosméticos e suprimentos, nunca poder." },
            { "{0} You can register this character.", "{0} Você pode registrar este personagem." },
            { "Marks {0} (earned {1})   Graduates {2}   Today {3}/{4} marks, {5}   Month {6}/{7} marks, {8}/{9} new", "Marcas {0} (ganhas {1})   Formados {2}   Hoje {3}/{4} marcas, {5}   Mês {6}/{7} marcas, {8}/{9} novos" },
            { "Mentors only", "Só mentores" }, { "Next week", "Semana que vem" }, { " ({0} left this week)", " ({0} restantes nesta semana)" }, { "marks", "marcas" },
            { "A mentor hunts with you and you both earn rewards. While you hunt together you get +{0}% experience and take {1}% less damage.", "Um mentor caça com você e vocês dois ganham recompensas. Enquanto caçam juntos, você ganha +{0}% de experiência e leva {1}% menos dano." },
            { "1 mentor who speaks your language is online now.", "1 mentor que fala o seu idioma está online agora." }, { "{0} mentors who speak your language are online now.", "{0} mentores que falam o seu idioma estão online agora." },
            { "1 mentor is online now.", "1 mentor está online agora." }, { "{0} mentors are online now.", "{0} mentores estão online agora." },
            { "No mentor is online right now: pick one and hunt together later.", "Nenhum mentor está online agora: escolha um e cacem juntos depois." },
            { "Mentors", "Mentores" }, { "Find a mentor?", "Achar um mentor?" }, { "A mentor can help you", "Um mentor pode ajudar você" }, { "Find a mentor", "Achar um mentor" }, { "No thanks", "Não, obrigado" },
            { "Looking for a mentor", "Procurando um mentor" }, { "any", "qualquer" }, { "Online", "Online" }, { "Press Search to see the mentors.", "Aperte Buscar para ver os mentores." },
            { "No mentor matches these filters.", "Nenhum mentor combina com estes filtros." }, { "Dismiss your mentor", "Dispensar seu mentor" },
            { "Milestones (your mentor earns Mentor Marks)", "Marcos (seu mentor ganha Marcas de Mentor)" },
            { "Graduation at level {0}: {1} for you, {2} Mentor Marks for your mentor (after {3} minutes hunting together). Dismissing your mentor ends the link.", "Formatura no nível {0}: {1} para você, {2} Marcas de Mentor para seu mentor (após {3} minutos caçando juntos). Dispensar seu mentor encerra o vínculo." },
            { "Apprentices ({0} / {1})", "Aprendizes ({0} / {1})" }, { "Since {0}, together {1}", "Desde {0}, juntos {1}" }, { "Release", "Liberar" }, { "Invite a character", "Convidar um personagem" },
            { "Your card", "Seu cartão" }, { "e.g. English, Portuguese", "ex.: inglês, português" }, { "Hours", "Horários" }, { "e.g. evenings", "ex.: à noite" }, { "a line for the list", "uma linha para a lista" },
            { "Accepting apprentices", "Aceitando aprendizes" }, { "Listed publicly", "Na lista pública" }, { "Save card", "Salvar cartão" }, { "Become a mentor", "Virar mentor" }, { "Retire", "Aposentar" },
            { "Type the character name first.", "Digite o nome do personagem primeiro." }, { "Your Mentor Marks: {0}", "Suas Marcas de Mentor: {0}" },
            { "Mentor Marks are earned by mentoring. Register in Mentoring.", "Marcas de Mentor se ganham sendo mentor. Registre-se em Mentoria." }, { "Nobody has graduated an apprentice yet.", "Ninguém formou um aprendiz ainda." },
            { "My mentor", "Meu mentor" }, { "Mentoring", "Mentoria" }, { "Marks Shop", "Loja de Marcas" }, { "Top Mentors", "Melhores mentores" },
            { "Any time", "Qualquer hora" }, { "Seen this week", "Visto nesta semana" }, { "Online now", "Online agora" }, { "Any class", "Qualquer classe" },
            // patch notes
            { "Server", "Servidor" }, { "Client", "Cliente" }, { "Content", "Conteúdo" }, { "Website", "Site" }, { "Client: next update", "Cliente: próxima atualização" }, { "Client {0}", "Cliente {0}" },
            { "NEW", "NOVO" }, { "Patch Notes", "Notas de atualização" }, { "No patch notes yet.", "Ainda não há notas de atualização." }, { "Week", "Semana" }, { "Open at login", "Abrir ao entrar" },
            { "The changelog is not available on this server.", "O registro de mudanças não está disponível neste servidor." }, { "Server updated: {0}", "Servidor atualizado: {0}" },
            { "Server updated: unknown", "Servidor atualizado: desconhecido" }, { "Client: Unity prototype", "Cliente: protótipo Unity" }, { "No change matches.", "Nenhuma mudança combina." },
            { "Patch notes", "Notas de atualização" }, { "Changelog", "Mudanças" },
            // drop feed, credits
            { "Unique and Divine only", "Só Únicos e Divinos" }, { "Legendary and better", "Lendário ou melhor" }, { "Drop Feed", "Feed de drops" },
            { "A line in the chat for each rare drop of a player. Choose which ones this client shows.", "Uma linha no chat para cada drop raro de um jogador. Escolha quais este cliente mostra." },
            { "Show drops", "Mostrar drops" }, { "Credits", "Créditos" },
            { "Cinders of Chaos is made with the work of these people and projects. Thank you!", "Cinders of Chaos é feito com o trabalho destas pessoas e projetos. Obrigado!" },
            { "Author: {0}", "Autor: {0}" }, { "Licence: {0}", "Licença: {0}" }, { "Used for: {0}", "Usado em: {0}" }, { "Source: {0}", "Fonte: {0}" },
            // streamer and cinema mode
            { "(private message hidden: streamer mode)", "(mensagem privada oculta: modo streamer)" }, { "Hidden character", "Personagem oculto" }, { "[hidden]", "[oculto]" }, { "On", "Ligado" },
            { "Streamer and cinema mode", "Modo streamer e cinema" }, { "For videos and streams. Streamer mode: Ctrl+Shift+S. Cinema mode: Ctrl+Shift+H.", "Para vídeos e transmissões. Modo streamer: Ctrl+Shift+S. Modo cinema: Ctrl+Shift+H." },
            { "Streamer mode", "Modo streamer" }, { "Also hide who sent a private message", "Também ocultar quem enviou uma mensagem privada" }, { "Also hide my name above my character", "Também ocultar meu nome acima do personagem" },
            { "Private message text, the other characters of the list and IP addresses in server messages are hidden.", "O texto das mensagens privadas, os outros personagens da lista e os endereços IP nas mensagens do servidor ficam ocultos." },
            { "Cinema mode", "Modo cinema" }, { "Also hide the names and bars of other players", "Também ocultar os nomes e barras de outros jogadores" },
            { "Cinema mode is on", "O modo cinema está ligado" }, { "Cinema mode is off", "O modo cinema está desligado" }, { "Show the interface", "Mostrar a interface" }, { "Hide the interface", "Ocultar a interface" },
            // performance
            { "Performance", "Desempenho" }, { "The last 10 seconds. Record 60 s writes a CSV and a text summary in the client's data folder.", "Os últimos 10 segundos. Gravar 60 s escreve um CSV e um resumo em texto na pasta de dados do cliente." },
            { "Measuring...", "Medindo..." }, { "FPS", "FPS" }, { "Average and lowest", "Média e mínimo" }, { "Frame time", "Tempo de quadro" }, { "Worst frame", "Pior quadro" }, { "Managed memory", "Memória gerenciada" },
            { "Creatures on screen", "Criaturas na tela" }, { "Open windows", "Janelas abertas" }, { "Recording: {0} of {1} s", "Gravando: {0} de {1} s" }, { "Record 60 s", "Gravar 60 s" },
            { "Summary copied.", "Resumo copiado." }, { "Last record: {0}", "Última gravação: {0}" },
            // screenshots
            { "Screenshot saved in {0}", "Captura de tela salva em {0}" }, { "Screenshots", "Capturas de tela" },
            { "A picture of the game window at the great moments, saved in the screenshots folder of the client's data folder.", "Uma imagem da janela do jogo nos grandes momentos, salva na pasta de capturas dentro da pasta de dados do cliente." },
            { "Automatic screenshots", "Capturas automáticas" }, { "Boss Defeated is not available in this client yet.", "Chefe derrotado ainda não está disponível neste cliente." },
            { "Level Up", "Subir de nível" }, { "Valuable Loot", "Loot valioso" }, { "Boss Defeated", "Chefe derrotado" }, { "Achievement", "Conquista" }, { "New Record", "Novo recorde" },
            // Customise Character
            { "Outline", "Contorno" }, { "Footprints", "Pegadas" }, { "Loot label", "Rótulo de loot" }, { "Chat colour", "Cor do chat" }, { "Spell effect", "Efeito de magia" }, { "Pet", "Pet" },
            { "Title frame", "Moldura do título" }, { "Nothing to change.", "Nada para mudar." }, { "Applied {0} change(s).", "{0} mudança(s) aplicada(s)." }, { "Customise Character", "Personalizar personagem" },
            { "The cosmetics you own. Outfit, mount, wings, aura and shader are in the Outfit window.", "Os cosméticos que você tem. Visual, montaria, asas, aura e shader estão na janela de Visual." },
            { "{0} more not unlocked yet. See Character > Cosmetics and the Store.", "Mais {0} ainda não desbloqueados. Veja Personagem > Cosméticos e a Loja." }, { "Apply the changes", "Aplicar as mudanças" },
        };
    }
}
