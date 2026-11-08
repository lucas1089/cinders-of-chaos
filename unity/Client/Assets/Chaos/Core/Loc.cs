// UI text in two languages, the way the main client does it (client/overlay/modules/client_chaos_locale): the English text
// is the key, `Loc.T("text", args)` looks it up in the table of the chosen language and falls back to the key. Languages:
// "en" (the keys themselves) and "pt-BR" (LocStrings.PtBr). Arguments use {0}, {1}; the translation keeps the same indexes.
// The first run takes pt-BR when the system language is Portuguese. The choice is the PlayerPrefs key "chaos.lang".
// Proper names (classes, spells, items, bosses) are not translated, as in the main client. Server texts come in the
// player's language from the server (opcode 157 hello with `lang`), not from here.
// A new window adds its texts to LocStrings.PtBr; Core.Tests scans the Unity sources and fails on a T("...") key without one.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public static class Loc
    {
        public const string English = "en", Portuguese = "pt-BR";
        public static readonly string[] Languages = { Portuguese, English };

        public static string Language { get; private set; } = English;
        static Dictionary<string, string> table = new Dictionary<string, string>();

        /// <summary>"pt", "pt-br", "pt_BR" -> pt-BR; "en", "en-US" -> en; anything else null.</summary>
        public static string Normalize(string lang)
        {
            if (string.IsNullOrEmpty(lang)) return null;
            string l = lang.ToLowerInvariant().Replace('_', '-');
            if (l == "pt" || l.StartsWith("pt-", StringComparison.Ordinal) || l.StartsWith("portugu", StringComparison.Ordinal)) return Portuguese;
            if (l == "en" || l.StartsWith("en-", StringComparison.Ordinal) || l.StartsWith("english", StringComparison.Ordinal)) return English;
            return null;
        }

        /// <summary>The saved choice, else the system's, else English.</summary>
        public static string Choose(string saved, string systemLanguage) => Normalize(saved) ?? Normalize(systemLanguage) ?? English;

        public static void Set(string lang)
        {
            Language = Normalize(lang) ?? English;
            table = Language == Portuguese ? LocStrings.PtBr : new Dictionary<string, string>();
        }

        /// <summary>The text in the chosen language; the key itself when it has no entry.</summary>
        public static string T(string key)
        {
            return table.TryGetValue(key, out var v) ? v : key;
        }

        public static string T(string key, params object[] args)
        {
            return string.Format(CultureInfo.InvariantCulture, T(key), args);
        }
    }

    /// <summary>pt-BR texts of the Unity windows: English key -> Brazilian Portuguese.</summary>
    public static class LocStrings
    {
        public static readonly Dictionary<string, string> PtBr = new Dictionary<string, string>
        {
            // SpellbookWindow
            { "Spells", "Magias" },
            { "Learned", "Aprendidas" },
            { "Available soon", "Em breve" },
            { "My vocation", "Minha classe" },
            { "All spells", "Todas as magias" },
            { "Runes", "Runas" },
            { "All types", "Todos os tipos" },
            { "Attack", "Ataque" },
            { "Support", "Suporte" },
            { "Search", "Buscar" },
            { "Loading spells...", "Carregando magias..." },
            { "No spell matches.", "Nenhuma magia encontrada." },
            { "Click a spell to cast it. Right-click to put it on a hotkey.", "Clique numa magia para lançar. Clique direito para pôr num atalho." },
            { "Level {0}", "Nível {0}" },
            { "Magic level {0}", "Nível mágico {0}" },
            { "Mana {0}", "Mana {0}" },
            { "Cooldown {0}s", "Recarga {0}s" },
            { "Words: {0}", "Palavras: {0}" },
            { "Put on a hotkey:", "Pôr num atalho:" },
            { "Pick a spell for F{0}", "Escolha uma magia para F{0}" },
            { "Wrong vocation", "Outra classe" },
            { "Needs learning", "Precisa aprender" },
            { "Locked quest spell", "Magia de missão bloqueada" },
            { "Level too low", "Nível baixo demais" },
            // HotkeyBarWindow
            { "Hotkeys", "Atalhos" },
            { "Click a slot to set what it says. Right-click: pick a spell.", "Clique num espaço para definir o que ele diz. Clique direito: escolher magia." },
            // NpcTalkWindow, NpcTradeWindow
            { "NPC", "NPC" },
            { "Nobody is talking to you.", "Ninguém está falando com você." },
            { "Send", "Enviar" },
            { "hi", "oi" },
            { "trade", "negociar" },
            { "bye", "tchau" },
            { "yes", "sim" },
            { "no", "não" },
            { "Trade", "Negociar" },
            { "No shop is open. Say hi and trade to an NPC.", "Nenhuma loja aberta. Diga hi e trade a um NPC." },
            { "Gold", "Ouro" },
            { "{0}: {1}", "{0}: {1}" },
            { "Capacity: {0}", "Capacidade: {0}" },
            { "Buy", "Comprar" },
            { "Sell", "Vender" },
            { "Nothing for sale.", "Nada à venda." },
            { "The NPC buys nothing you carry.", "O NPC não compra nada do que você leva." },
            { "Price {0}", "Preço {0}" },
            { "Amount", "Quantidade" },
            { "Total: {0}", "Total: {0}" },
            { "Ignore capacity", "Ignorar capacidade" },
            { "Ignore equipped", "Ignorar equipados" },
            { "Not enough money.", "Dinheiro insuficiente." },
            { "Not enough capacity.", "Capacidade insuficiente." },
            { "OK", "OK" },
            // PartyFramesWindow, party menu, character plate, character select
            { "Party", "Grupo" },
            { "Party ({0})", "Grupo ({0})" },
            { "Not in a party", "Fora de grupo" },
            { "XP off", "XP desligado" },
            { "Invite a player...", "Convidar jogador..." },
            { "Invite", "Convidar" },
            { "Invitation sent to {0}.", "Convite enviado para {0}." },
            { "You are not in a party. Invite a player here, or right-click a player on the map.", "Você não está em um grupo. Convide um jogador aqui, ou clique com o botão direito em um jogador no mapa." },
            { "Lv {0}", "Nv {0}" },
            { "Connection lost", "Conexão perdida" },
            { "Dead", "Morto" },
            { "far", "longe" },
            { "{0} up", "{0} acima" },
            { "{0} down", "{0} abaixo" },
            { "{0} invited you to join their party.", "{0} convidou você para o grupo dele." },
            { "Accept", "Aceitar" },
            { "Decline", "Recusar" },
            { "Stop Attack", "Parar ataque" },
            { "Follow", "Seguir" },
            { "Stop following", "Parar de seguir" },
            { "Remove from the party", "Remover do grupo" },
            { "Copy Name", "Copiar nome" },
            { "{0} is out of sight: go near to join the party.", "{0} está fora de vista: chegue perto para entrar no grupo." },
            { "Invite to Party", "Convidar para o grupo" },
            { "Join Party", "Entrar no grupo" },
            { "Revoke Invitation", "Cancelar convite" },
            { "Pass Leadership", "Passar a liderança" },
            { "Leave Party", "Sair do grupo" },
            { "Enable Shared Experience", "Ativar experiência compartilhada" },
            { "Disable Shared Experience", "Desativar experiência compartilhada" },
            { "{0}% to level {1}", "{0}% para o nível {1}" },
            { "Characters", "Personagens" },
            { "No characters on this account. Create one on the website.", "Nenhum personagem nesta conta. Crie um no site." },
            { "Enter game", "Entrar no jogo" },
            { "Create character", "Criar personagem" },
            { "Back", "Voltar" },
            // chat, channels, death, fight modes (ChaosApp.Chat.cs, ChannelsWindow, FightWindow)
            { "Chat", "Conversa" },
            { "Default", "Padrão" },
            { "Server Log", "Registro do servidor" },
            { "Press Enter to talk", "Aperte Enter para falar" },
            { "Channels", "Canais" },
            { "Loading channels...", "Carregando canais..." },
            { "No channels.", "Nenhum canal." },
            { "Message to", "Mensagem para" },
            { "Open", "Abrir" },
            { "Death", "Morte" },
            { "You are dead.", "Você morreu." },
            { "You died.", "Você morreu." },
            { "Experience and skill loss: {0}% of the normal penalty.", "Perda de experiência e habilidades: {0}% da penalidade normal." },
            { "Fight", "Combate" },
            { "Offensive", "Ofensivo" },
            { "Balanced", "Equilibrado" },
            { "Defensive", "Defensivo" },
            { "Stand", "Parado" },
            { "Chase", "Perseguir" },
            { "Secure mode", "Modo seguro" },
            // HelperWindow (combat helper, HelperRotation.cs)
            { "Helper", "Ajudante" },
            { "(empty)", "(vazio)" },
            { "Helper off", "Ajudante desligado" },
            { "Paused: protection zone", "Pausado: zona de proteção" },
            { "Paused: following", "Pausado: seguindo" },
            { "Paused: waiting for the server", "Pausado: esperando o servidor" },
            { "Running", "Em execução" },
            { "Helper on", "Ajudante ligado" },
            { "Healing", "Cura" },
            { "Shooter", "Atirador" },
            { "Target", "Alvo" },
            { "Healing spells", "Magias de cura" },
            { "% health", "% de vida" },
            { "Potions", "Poções" },
            { "mana", "mana" },
            { "health", "vida" },
            { "% mana", "% de mana" },
            { "Right-click a spirit potion row to switch it between health and mana.", "Clique com o botão direito numa poção de espírito para alternar entre vida e mana." },
            { "Mana training", "Treino de mana" },
            { "Auto haste", "Pressa automática" },
            { "In protection zone", "Em zona de proteção" },
            { "Spell rotation", "Rotação de magias" },
            { "Auto turn", "Virar sozinho" },
            { "Spells are tried from the top; a slot casts when the mana and the monster count are met.", "As magias são tentadas de cima para baixo; um espaço lança quando a mana e o número de monstros são atingidos." },
            { "Mana percent and the number of monsters to cast on.", "Porcentagem de mana e número de monstros para lançar." },
            { "Auto setup", "Configuração automática" },
            { "No rotation for this class and level yet (is the spell list loaded?).", "Ainda não há rotação para esta classe e nível (a lista de magias carregou?)." },
            { "Clear slots", "Limpar espaços" },
            { "Auto target", "Alvo automático" },
            { "Attacks a monster within 7 x 5 tiles by the rule below and keeps it until it is gone.", "Ataca um monstro a até 7 x 5 casas pela regra abaixo e o mantém até ele sumir." },
            { "Rotation set: {0} (max gap {1} s)", "Rotação definida: {0} (maior intervalo {1} s)" },
            { "Closest", "Mais próximo" },
            { "Farthest", "Mais distante" },
            { "Lowest health", "Menor vida" },
            { "Highest health", "Maior vida" },
            { "Most monsters around it", "Mais monstros ao redor" },
            { "Closest, then lowest health", "Mais próximo, depois menor vida" },
            { "Closest, then highest health", "Mais próximo, depois maior vida" },
            { "Farthest, then lowest health", "Mais distante, depois menor vida" },
            // DeathRecapWindow (DeathRecap.cs)
            { "Recap", "Resumo" },
            { "Open after a death", "Abrir depois de uma morte" },
            { "Last deaths", "Últimas mortes" },
            { "No deaths yet.", "Nenhuma morte ainda." },
            { "No death to show", "Nenhuma morte para mostrar" },
            { "No death recorded yet.", "Nenhuma morte registrada ainda." },
            { "{0}, {1} hit", "{0}, {1} acerto" },
            { "{0}, {1} hits", "{0}, {1} acertos" },
            { "{0}% critical", "{0}% críticos" },
            { "mana {0}", "mana {0}" },
            { "No hits were recorded before this death.", "Nenhum acerto foi registrado antes desta morte." },
            { "What to do", "O que fazer" },
            { "Final hits", "Golpes finais" },
            { "Other", "Outros" },
            { "Unknown", "Desconhecido" },
            { "Player", "Jogador" },
            { "Yourself", "Você mesmo" },
            { "Environment", "Ambiente" },
            { "Hidden", "Oculto" },
            { "Others", "Outros" },
            { "Monster", "Monstro" },
            { "Killing blow: {0}", "Golpe final: {0}" },
            { "Killing blow: {0}, {1} {2}{3}{4}", "Golpe final: {0}, {1} {2}{3}{4}" },
            { "(critical)", "(crítico)" },
            { "(mana)", "(mana)" },
            { "Defeated by {0}", "Derrotado por {0}" },
            { "Killed by {0}", "Morto por {0}" },
            { "level {0}", "nível {0}" },
            { "Nothing lost", "Nada perdido" },
            { "Experience lost: shown at your next login", "Experiência perdida: aparece no seu próximo login" },
            { "No experience lost", "Nenhuma experiência perdida" },
            { "Lost {0} experience", "Perdeu {0} de experiência" },
            { " and {0} level", " e {0} nível" },
            { " and {0} levels", " e {0} níveis" },
            { "No hits recorded before the death", "Nenhum acerto registrado antes da morte" },
            { "Last {0} before the death, {1} hit", "Últimos {0} antes da morte, {1} acerto" },
            { "Last {0} before the death, {1} hits", "Últimos {0} antes da morte, {1} acertos" },
            { "Damage taken: {0}", "Dano recebido: {0}" },
            { " (health {0}, mana {1})", " (vida {0}, mana {1})" },
            { "death", "morte" },
            { "Defeat", "Derrota" },
            { "-{0} exp", "-{0} exp" },
            { ", -{0} lvl", ", -{0} nív" },
            { "These monsters are {0} levels above you: Next Goals shows hunts for your level", "Estes monstros estão {0} níveis acima de você: Próximos objetivos mostra caçadas para o seu nível" },
            { "You used no potions: set up healing in the Helper (Auto setup)", "Você não usou poções: configure a cura no Helper (Configuração automática)" },
            { "Your healing covered only {0}% of the damage: heal sooner or pull fewer monsters", "Sua cura cobriu só {0}% do dano: cure-se mais cedo ou puxe menos monstros" },
            { "{0} monsters hit you at once: pull fewer at a time", "{0} monstros atacaram você ao mesmo tempo: puxe menos de cada vez" },
            { "Most damage was fire and your fire resistance is {0}%: look for fire resistance on gear or a ruby in jewellery", "A maior parte do dano foi de fogo e sua resistência a fogo é {0}%: procure resistência a fogo nos equipamentos ou um rubi nas joias" },
            { "Most damage was ice and your ice resistance is {0}%: look for ice resistance on gear or a sapphire in jewellery", "A maior parte do dano foi de gelo e sua resistência a gelo é {0}%: procure resistência a gelo nos equipamentos ou uma safira nas joias" },
            { "Most damage was earth and your earth resistance is {0}%: look for earth resistance on gear or an emerald in jewellery", "A maior parte do dano foi de terra e sua resistência a terra é {0}%: procure resistência a terra nos equipamentos ou uma esmeralda nas joias" },
            { "Most damage was holy and your holy resistance is {0}%: look for holy resistance on gear or a diamond in jewellery", "A maior parte do dano foi sagrado e sua resistência a sagrado é {0}%: procure resistência a sagrado nos equipamentos ou um diamante nas joias" },
            { "Most damage was death and your death resistance is {0}%: look for death resistance on gear or an amethyst in armour", "A maior parte do dano foi de morte e sua resistência a morte é {0}%: procure resistência a morte nos equipamentos ou uma ametista na armadura" },
            { "Most damage was energy and your energy resistance is {0}%: look for energy resistance on gear or a topaz in armour", "A maior parte do dano foi de energia e sua resistência a energia é {0}%: procure resistência a energia nos equipamentos ou um topázio na armadura" },
            { "Most damage was physical and your physical resistance is {0}%: look for physical resistance on gear or an onyx in armour", "A maior parte do dano foi físico e sua resistência física é {0}%: procure resistência física nos equipamentos ou um ônix na armadura" },
            { "Physical", "Físico" },
            { "Fire", "Fogo" },
            { "Earth", "Terra" },
            { "Energy", "Energia" },
            { "Ice", "Gelo" },
            { "Holy", "Sagrado" },
            { "Drown", "Afogamento" },
            { "Life drain", "Dreno de vida" },
            { "Mana drain", "Dreno de mana" },
            // LootWindow, ground labels (LootFilter.cs, GroundLabels.cs)
            { "Loot", "Loot" },
            { "Filter", "Filtro" },
            { "Labels", "Rótulos" },
            { "Nothing looted yet. Kills drop their items here.", "Nada lootado ainda. Os abates deixam seus itens aqui." },
            { "Nothing to loot", "Nada para lootear" },
            { "Loading...", "Carregando..." },
            { "Presets", "Predefinições" },
            { "Glow on gear from", "Brilho em equipamento a partir de" },
            { "Dim gear below", "Esmaecer equipamento abaixo de" },
            { "Glow on a modifier of", "Brilho em um modificador de" },
            { "Off", "Desligado" },
            { "Show", "Mostrar" },
            { "Unchecked categories are dimmed (still lootable). Uniques and orbs always glow.", "Categorias desmarcadas ficam esmaecidas (ainda dá para lootear). Únicos e orbes sempre brilham." },
            { "Rare-drop message", "Mensagem de drop raro" },
            { "Names over the items on the ground, by these rules", "Nomes sobre os itens no chão, por estas regras" },
            { "Ground labels", "Rótulos no chão" },
            { "Magic and better always get a label", "Magic ou melhor sempre ganha um rótulo" },
            { "Hold Alt to show every item", "Segure Alt para mostrar todos os itens" },
            { "Corpse labels", "Rótulos de corpos" },
            { "Decay timers", "Tempo até sumir" },
            { "Size", "Tamanho" },
            { "Small", "Pequeno" },
            { "Normal", "Normal" },
            { "Large", "Grande" },
            { "Click a corpse label to open the corpse.", "Clique no rótulo de um corpo para abri-lo." },
            { "Unique", "Única" },
            { "Equipment", "Equipamento" },
            { "Currency (orbs, coins)", "Moeda (orbes, coins)" },
            { "Supplies (potions, runes)", "Suprimentos (poções, runas)" },
            { "Looted (or gone)", "Saqueado (ou sumiu)" },
            { "{0} left in the corpse", "{0} restantes no corpo" },
            { "Click: loot all   Shift+click: loot one", "Clique: lootear tudo   Shift+clique: lootear um" },
            { "Click: loot", "Clique: lootear" },
            { "Corpse: {0} item", "Corpo: {0} item" },
            { "Corpse: {0} items", "Corpo: {0} itens" },
        };
    }
}
