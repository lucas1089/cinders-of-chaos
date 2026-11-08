// pt-BR texts of the helper extras and the info windows (O433 phase 5, track Q): helper Runes / Allies / Support / More tabs, shooter presets, the bot HUD, the DPS meter,
// the Codex, the help search, the How it works card and the weapon list. Merged into LocStrings.PtBr by its static constructor (a key the main table has wins).
// Keys are the English text. The Codex, How it works and help texts come from the generated data: How it works and the help search carry their own pt-BR in the data.
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class LocInfo
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            // helper window: tabs and shooter presets
            { "Runes", "Runas" }, { "Allies", "Aliados" }, { "Support", "Suporte" }, { "More", "Mais" }, { "Preset", "Predefinição" }, { "New", "Novo" }, { "Copy", "Copiar" },
            { "Rename", "Renomear" }, { "Delete", "Excluir" }, { "Preset made.", "Predefinição criada." }, { "Preset renamed.", "Predefinição renomeada." },
            { "Preset deleted.", "Predefinição excluída." }, { "The last preset stays.", "A última predefinição fica." },
            { "The name cannot be empty.", "O nome não pode ficar vazio." }, { "The name cannot be longer than 12 characters.", "O nome não pode ter mais de 12 caracteres." },
            { "The name can only have letters, digits, spaces, - and _.", "O nome só pode ter letras, números, espaços, - e _." },
            { "There is already a preset with this name.", "Já existe uma predefinição com esse nome." }, { "There are too many presets.", "Há predefinições demais." },
            // runes
            { "Healing runes (on yourself)", "Runas de cura (em você)" }, { "Attack runes (on the target, with the spell rotation on)", "Runas de ataque (no alvo, com a rotação de magias ligada)" },
            { "% from", "% de" }, { "% up to", "% até" },
            { "A rune is used when the monsters in its area reach the count and the target's health fits. 0% up to means no limit. Runes must be in your equipment or an open bag. Each kind of rune waits a second.",
              "Uma runa é usada quando os monstros na sua área atingem a quantidade e a vida do alvo combina. 0% até significa sem limite. As runas precisam estar no seu equipamento ou numa bolsa aberta. Cada tipo de runa espera um segundo." },
            // allies
            { "Heal the party", "Curar o grupo" }, { "Heal friends", "Curar amigos" }, { "Single spell", "Magia única" }, { "Group spell", "Magia em grupo" }, { "Healing rune", "Runa de cura" },
            { "Your own healing comes first. Only players in the helper's 7 x 5 window are healed, a protection zone pauses it, and each player gets a heal at most every 1.2 seconds.",
              "Sua própria cura vem primeiro. Só jogadores na janela de 7 x 5 do ajudante são curados, uma zona de proteção pausa, e cada jogador recebe uma cura no máximo a cada 1,2 segundos." },
            // support
            { "Support on", "Suporte ligado" }, { "Mana kept after a cast: {0}%", "Mana mantida após uma magia: {0}%" }, { "Add spell", "Adicionar magia" },
            { "Fill from my class", "Preencher com a minha classe" }, { "{0} support spells set.", "{0} magias de suporte definidas." },
            { "No support spells for this class and level yet (is the spell list loaded?).", "Ainda não há magias de suporte para esta classe e nível (a lista de magias carregou?)." },
            { "Spells are cast when off cooldown and while their effect is not on. Fight buffs wait for a monster.", "As magias são lançadas quando saem do tempo de recarga e enquanto o efeito não está ativo. Buffs de luta esperam um monstro." },
            { "Casting", "Lançando" }, { "Active", "Ativo" }, { "Cooldown", "Recarga" }, { "Waiting", "Esperando" }, { "Waits for a fight", "Espera uma luta" }, { "No mana", "Sem mana" },
            { "Mana reserve", "Reserva de mana" }, { "Not castable", "Não pode lançar" }, { "Off", "Desligado" }, { "Next", "Próxima" }, { "Rate limit", "Limite de ritmo" },
            { "Casting another spell", "Lançando outra magia" }, { "Resting", "Descansando" }, { "Summon is out", "Invocação em campo" }, { "Summon limit", "Limite de invocações" },
            { "Cannot count summons", "Não conta as invocações" }, { "Needs the buff bar", "Precisa da barra de buffs" }, { "Needs a party", "Precisa de um grupo" },
            { "Utility, never cast", "Utilidade, nunca lançada" }, { "Unknown spell", "Magia desconhecida" },
            // more: food, bot HUD, Everfull
            { "Auto eat food", "Comer automaticamente" }, { "Eats a carried food every two minutes. Food must be in your equipment or an open bag.", "Come uma comida que você carrega a cada dois minutos. A comida precisa estar no equipamento ou numa bolsa aberta." },
            { "Show Bot HUD", "Mostrar HUD do ajudante" }, { "Size: {0}", "Tamanho: {0}" }, { "Compact", "Compacto" }, { "Normal", "Normal" }, { "Wide", "Largo" },
            { "Everfull flasks carried", "Frascos Everfull carregados" }, { "Health slot: {0}", "Espaço de vida: {0}" }, { "Mana slot: {0}", "Espaço de mana: {0}" }, { "none", "nenhum" },
            { "A health or mana potion row on the stock potion drinks the Everfull flask you carry in that slot.", "Uma linha de poção de vida ou mana na poção comum bebe o frasco Everfull que você carrega nesse espaço." },
            { "Bot HUD", "HUD do ajudante" }, { "Active: {0} modules", "Ativos: {0} módulos" }, { "Standby", "Em espera" }, { "Combat", "Combate" }, { "Healing", "Cura" }, { "Player", "Jogador" },
            { "Auto", "Auto" }, { "Shooter", "Atirador" }, { "{0} spells", "{0} magias" }, { "{0} potions", "{0} poções" }, { "Haste {0}", "Pressa {0}" }, { "Train {0}%", "Treino {0}%" },
            { "HP {0}%  MP {1}%  Lv {2}", "PV {0}%  PM {1}%  Nv {2}" }, { "Pick sections in the Helper window", "Escolha as seções na janela do Ajudante" },
            // DPS meter
            { "DPS Meter", "Medidor de DPS" }, { "Combat log", "Registro de combate" }, { "Fight summary copied to the clipboard.", "Resumo da luta copiado para a área de transferência." },
            { "To chat", "Para o chat" }, { "Share with party", "Compartilhar com o grupo" }, { "Reset...", "Zerar..." }, { "Sure?", "Certeza?" },
            { "Nothing in this tab yet.", "Nada nesta aba ainda." }, { "hits", "acertos" }, { "critical", "críticos" }, { "avg", "média" }, { "max", "máx" }, { "overhealing", "cura em excesso" },
            { "A keystone note: how much it changed. Already counted in the other rows.", "Uma nota de pedra angular: quanto ela mudou. Já contada nas outras linhas." },
            { "No party numbers yet.", "Ainda sem números do grupo." }, { "Source", "Origem" }, { "Elements: ", "Elementos: " },
            { "Dmg", "Dano" }, { "Taken", "Sofrido" }, { "Recv", "Receb." }, { "Heal", "Cura" }, { "Damage", "Dano" }, { "Received", "Recebido" },
            { "Total", "Total" }, { "Per s", "Por s" }, { "Hits", "Acertos" }, { "Crit", "Crít." }, { "Avg", "Média" }, { "Max", "Máx" }, { "Over", "Excesso" },
            { "Current fight", "Luta atual" }, { "Session", "Sessão" }, { "Boss", "Chefe" }, { "No fight yet", "Nenhuma luta ainda" }, { "Fight", "Luta" },
            { "Physical", "Físico" }, { "Fire", "Fogo" }, { "Earth", "Terra" }, { "Energy", "Energia" }, { "Ice", "Gelo" }, { "Holy", "Sagrado" }, { "Death", "Morte" }, { "Drown", "Afogamento" },
            { "Life drain", "Dreno de vida" }, { "Mana drain", "Dreno de mana" },
            // Codex, help search, How it works, weapon list
            { "Codex", "Códice" }, { "The Codex data is missing from this build.", "Os dados do Códice não estão nesta versão." }, { "Nothing found.", "Nada encontrado." },
            { "Where to find: tier {0}", "Onde achar: nível {0}" }, { "Where to find: drops, shops, recipes and rewards", "Onde achar: drops, lojas, receitas e recompensas" },
            { "Marked: the tiers that roll at item level {0} ({1}).", "Marcado: os níveis que saem no nível de item {0} ({1})." }, { "See: {0}", "Veja: {0}" },
            { "Nothing to show", "Nada para mostrar" }, { "Help", "Ajuda" }, { "Help Search", "Buscar Ajuda" }, { "Ask a question: how do I get orbs?", "Faça uma pergunta: como consigo orbes?" },
            { "Nothing found. Try other words.", "Nada encontrado. Tente outras palavras." }, { "Codex: {0}", "Códice: {0}" }, { "Search...", "Buscar..." },
            { "Open the card the first time I open a window", "Abrir o cartão na primeira vez que eu abrir uma janela" }, { "How it works", "Como funciona" },
            { "What it is", "O que é" }, { "Who is it for", "Para quem é" }, { "Monster levels", "Níveis dos monstros" }, { "What drops", "O que cai" }, { "If you die", "Se você morrer" }, { "How often", "Com que frequência" },
            { "Weapon Proficiency", "Proficiência de Arma" }, { "{0} weapons. The perk trees and weapon experience are not in this client yet.", "{0} armas. As árvores de vantagens e a experiência da arma ainda não estão neste cliente." },
            { "All", "Todas" }, { "Axes", "Machados" }, { "Clubs", "Clavas" }, { "Distance Weapons", "Armas à Distância" }, { "Swords", "Espadas" }, { "Wands and Rods", "Varinhas e Cajados" }, { "Fist Weapons", "Armas de Punho" },
        };
    }
}
