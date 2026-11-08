// pt-BR texts of the HUD models and windows (track H), merged into LocStrings.PtBr by its static constructor. Entries that
// LocStrings already has win; a test (HudTests) checks that every key the HUD asks for exists.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class HudStrings
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            // toast titles (ToastKinds) and the danger line
            { "GAMEMASTER NOTIFICATION", "NOTIFICAÇÃO DO GAMEMASTER" }, { "TASK COMPLETED", "TASK COMPLETA" }, { "BATTLE PASS REWARD", "RECOMPENSA DO BATTLE PASS" },
            { "PARTY INVITATION", "CONVITE DE GRUPO" }, { "BOUNTY BOARD", "QUADRO DE CAÇADAS" }, { "NEW ADVENTURER", "NOVO AVENTUREIRO" },
            { "BESTIARY", "BESTIÁRIO" }, { "ACHIEVEMENT UNLOCKED", "CONQUISTA DESBLOQUEADA" }, { "ASCENSION", "ASCENSÃO" }, { "MARKET", "MERCADO" },
            { "ITEM SOLD", "ITEM VENDIDO" }, { "INVASION", "INVASÃO" }, { "CURSED CHEST", "BAÚ AMALDIÇOADO" }, { "WEEKLY CHEST", "BAÚ SEMANAL" },
            { "LEVEL MILESTONE", "MARCO DE NÍVEL" }, { "SEASON PASS", "PASSE DA TEMPORADA" }, { "CHAOS PACT", "PACTO DO CAOS" },
            { "SEASONAL JOURNEY", "JORNADA DA TEMPORADA" }, { "BOSS PASSIVE POINT", "PONTO PASSIVO DE BOSS" }, { "SCREENSHOT", "CAPTURA DE TELA" },
            { "CATACOMB AVAILABLE", "CATACUMBA DISPONÍVEL" }, { "CAUTION", "CUIDADO" }, { "DANGER", "PERIGO" },
            { "Task Complete: of {0}, killed {1} and received {2} task points", "Task completa: de {0}, matou {1} e recebeu {2} pontos de task" },
            { "Mission Complete: {0} and received {1} battle pass exp", "Missão completa: {0} e recebeu {1} de exp do battle pass" },
            { "{0} [{1}] invited you to join their party for catacomb {2} level {3}!", "{0} [{1}] convidou você para o grupo dele na catacumba {2} nível {3}!" },
            { "The {0} Catacomb Level {1} is now free!", "A Catacumba {0} nível {1} está livre!" },
            { "Accept", "Aceitar" }, { "Decline", "Recusar" }, { "Start", "Iniciar" },
            // buff bar
            { "  (debuff)", "  (debuff)" }, { "Stacks: {0}", "Acúmulos: {0}" }, { "Time left: {0}", "Tempo restante: {0}" }, { "No time limit", "Sem limite de tempo" },
            { "Hold Alt for what it does.", "Segure Alt para ver o que faz." },
            // cast bar results
            { "Interrupted: moved", "Interrompida: você se mexeu" }, { "Interrupted: paralysed", "Interrompida: paralisia" }, { "Interrupted", "Interrompida" },
            { "Interrupted: new spell", "Interrompida: nova magia" }, { "Interrupted: portal", "Interrompida: portal" }, { "Cancelled", "Cancelada" },
            { "Failed", "Falhou" }, { "Interrupted: hit", "Interrompida: golpe" }, { "Refused", "Recusada" },
            // shield
            { "Shield", "Escudo" },
            // monster bar
            { "Magic", "Mágico" }, { "Rare", "Raro" }, { "Legendary", "Lendário" }, { "Rift Guardian", "Guardião da Fenda" }, { "Omen Guardian", "Guardião do Presságio" },
            { "Lv {0}", "Nv {0}" }, { "interrupted", "interrompida" },
            { "move out", "saia da área" }, { "kill the totem", "mate o totem" }, { "stand in the circle", "fique no círculo" }, { "hide behind a pillar", "esconda-se atrás de um pilar" },
            { "Blazing: its hits may set you on fire (30%).", "Flamejante: seus golpes podem incendiar você (30%)." },
            { "Chilling: its hits may slow you for 3 seconds (25%).", "Gélido: seus golpes podem deixar você lento por 3 segundos (25%)." },
            { "Venomous: its hits may poison you (30%).", "Venenoso: seus golpes podem envenenar você (30%)." },
            { "Shocking: its hits may electrify you (25%).", "Chocante: seus golpes podem eletrocutar você (25%)." },
            { "Vampiric: heals 30% of the damage it deals.", "Vampírico: cura 30% do dano que causa." },
            { "Berserker: deals 50% more damage below half health.", "Berserker: causa 50% a mais de dano abaixo da metade da vida." },
            { "Brutal: deals 40% more damage.", "Brutal: causa 40% a mais de dano." },
            { "Stoneskin: takes 30% less damage.", "Pele de pedra: recebe 30% a menos de dano." },
            { "Reflective: returns 15% of the damage it takes.", "Refletor: devolve 15% do dano que recebe." },
            { "Regenerating: heals 2% of its health every 2.5 seconds.", "Regenerador: cura 2% da vida a cada 2,5 segundos." },
            { "Swift: moves faster.", "Veloz: move-se mais rápido." },
            { "Explosive: explodes on death (5% of its health, 2 tiles).", "Explosivo: explode ao morrer (5% da vida, 2 sqm)." },
            { "Juggernaut: 60% more health.", "Colosso: 60% a mais de vida." },
            // anti-bot and reports
            { "Presence check", "Verificação de presença" }, { "Click the picture of: {0}", "Clique na imagem de: {0}" }, { "Another picture", "Outra imagem" },
            { "No more pictures", "Sem mais imagens" }, { "A new picture. Take your time.", "Uma imagem nova. Sem pressa." }, { "Try again.", "Tente de novo." },
            { "Checking...", "Verificando..." },
            { "Report Player", "Denunciar jogador" }, { "Character", "Personagem" }, { "Reason", "Motivo" }, { "Note", "Nota" },
            { "Send report", "Enviar denúncia" }, { "Close", "Fechar" },
            { "Botting", "Uso de bot" }, { "Cheating / exploiting", "Trapaça / exploit" }, { "Harassment", "Assédio" }, { "Scam", "Golpe" },
            { "Offensive name", "Nome ofensivo" }, { "Other", "Outro" },
            { "Type the name of the character you want to report.", "Digite o nome do personagem que você quer denunciar." },
            { "You cannot report yourself.", "Você não pode denunciar a si mesmo." }, { "Choose a reason.", "Escolha um motivo." },
            { "Describe the problem in the note (reason Other).", "Descreva o problema na nota (motivo Outro)." },
            // options
            { "Options", "Opções" }, { "Language", "Idioma" }, { "Keep attacking while moving", "Continuar atacando ao andar" },
            { "Right-click equips items", "Clique direito equipa itens" }, { "Show the buff bar", "Mostrar a barra de buffs" }, { "Buff timers", "Tempo dos buffs" },
            { "Display scale: x{0}", "Escala de números: x{0}" }, { "Report a player...", "Denunciar um jogador..." },
        };
    }
}
