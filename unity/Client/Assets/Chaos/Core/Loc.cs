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
        };
    }
}
