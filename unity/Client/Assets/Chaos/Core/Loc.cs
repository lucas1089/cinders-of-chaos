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
        // the items and economy windows keep their texts in LocItems.cs (merged below, so a key two files share is not an error)
        static LocStrings() { foreach (var kv in LocItems.PtBr) PtBr[kv.Key] = kv.Value; }

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
        };
    }
}
