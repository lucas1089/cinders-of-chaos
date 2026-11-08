// "How it works" cards (O433 phase 5, track Q): ONE shared card that explains a feature in very plain words: who it is for, the monster levels, what drops,
// what a death costs, how often. A port of game_howitworks/howcore.lua and howitworks.lua. The texts are generated from the server configs
// (Resources/HowItWorks.json, unity/tools/gen_info_data.lua from howitworks_data.lua); no opcode.
//   HowData.Features = [{key, title {en, pt}, window?, unlocks?, goals?, rows [{id, en, pt}]}]; a row id is one of HowItWorks.Rows.
// First open (owner request 2026-11-03): a feature window opens its card by itself the first time a character opens it, once per character and card
// (PlayerPrefs chaos.howitworks.seen.<character>), unless the card's check box turned that off (chaos.howitworks.auto).
// Tests: Core.Tests/InfoTests.cs (mirrors howcore_test.lua).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class HowRow { public string Id = "", En = "", Pt = ""; }

    public sealed class HowCard
    {
        public string Key = "", Window = "";
        public string TitleEn = "", TitlePt = "";
        public readonly List<string> Unlocks = new List<string>(), Goals = new List<string>();
        public readonly List<HowRow> Rows = new List<HowRow>();
    }

    public sealed class HowItWorks
    {
        /// <summary>The rows of a card, in order (the window has a heading for each).</summary>
        public static readonly string[] Rows = { "what", "who", "levels", "drops", "death", "often" };

        public readonly List<HowCard> Cards = new List<HowCard>();
        readonly Dictionary<string, HowCard> byKey = new Dictionary<string, HowCard>(), byUnlock = new Dictionary<string, HowCard>(),
            byGoal = new Dictionary<string, HowCard>(), byWindow = new Dictionary<string, HowCard>();

        public bool Ready => Cards.Count > 0;

        public static HowItWorks Load(string jsonText)
        {
            var h = new HowItWorks();
            object root = Json.TryParse(jsonText);
            foreach (object f in Json.List(root, "features"))
            {
                var c = new HowCard { Key = Json.Text(f, "key"), Window = Json.Text(f, "window") };
                var title = Json.Get(f, "title");
                c.TitleEn = Json.Text(title, "en"); c.TitlePt = Json.Text(title, "pt");
                foreach (object u in Json.List(f, "unlocks")) if (u is string us) c.Unlocks.Add(us);
                foreach (object g in Json.List(f, "goals")) if (g is string gs) c.Goals.Add(gs);
                foreach (object r in Json.List(f, "rows")) c.Rows.Add(new HowRow { Id = Json.Text(r, "id"), En = Json.Text(r, "en"), Pt = Json.Text(r, "pt") });
                if (c.Key.Length == 0) continue;
                h.Cards.Add(c);
                h.byKey[c.Key] = c;
                foreach (var u in c.Unlocks) if (!h.byUnlock.ContainsKey(u)) h.byUnlock[u] = c;
                foreach (var g in c.Goals) if (!h.byGoal.ContainsKey(g)) h.byGoal[g] = c;
                if (c.Window.Length > 0 && !h.byWindow.ContainsKey(c.Window)) h.byWindow[c.Window] = c;
            }
            return h;
        }

        static HowCard Get(Dictionary<string, HowCard> d, string key) { HowCard c; return key != null && d.TryGetValue(key, out c) ? c : null; }

        public HowCard Find(string key) => Get(byKey, key);
        public HowCard ForUnlock(string key) => Get(byUnlock, key);
        public HowCard ForGoal(string key) => Get(byGoal, key);
        /// <summary>The card of a feature window by the main client's module name (game_infinitytower) or the Unity window class (TowerWindow, see UnityWindows).</summary>
        public HowCard ForWindow(string module) => Get(byWindow, module);

        /// <summary>Unity window class to the card key (the main client names the module; a card without a Unity window is not here).</summary>
        public static readonly Dictionary<string, string> UnityWindows = new Dictionary<string, string>
        {
            { "TowerWindow", "tower" }, { "RiftAtlasWindow", "rift" }, { "ArenaWindow", "arena" }, { "BattlegroundWindow", "battleground" }, { "DungeonsWindow", "dungeons" },
            { "DescentWindow", "descent" }, { "RaidWindow", "raid" }, { "SiegeWindow", "siege" }, { "BountyWindow", "bounty" }, { "DailyWindow", "daily" },
            { "WeeklyChestWindow", "weeklychest" }, { "EmberCacheWindow", "embercache" }, { "SeasonWindow", "season" }, { "PassiveTreeWindow", "passive" },
            { "TownPortalWindow", "townportal" }, { "AutoLootWindow", "autoloot" }, { "StashWindow", "stash" }, { "PartyFinderWindow", "partyfinder" },
            { "GoalsWindow", "goals" }, { "SpellbookWindow", "spellbook" }, { "MarketWindow", "market" }, { "CraftingWindow", "crafting" }, { "PetsWindow", "pets" },
            { "FactionsWindow", "factions" }, { "ConquestWindow", "conquest" }, { "GuildWarWindow", "guildwar" }, { "PvpZoneWindow", "pvpzone" },
            { "ProfessionsWindow", "professions" }, { "TransmogWindow", "transmog" }, { "HideoutWindow", "hideout" }, { "CharmsWindow", "charms" },
            { "OrbExchangeWindow", "orbexchange" }, { "LoadoutsWindow", "loadouts" }, { "PassWindow", "seasonpass" }, { "InvasionWindow", "invasion" },
        };

        /// <summary>'pt-BR' (any 'pt...') picks Portuguese, everything else English.</summary>
        public static bool IsPt(string lang) => lang != null && lang.Length >= 2 && lang.Substring(0, 2).ToLowerInvariant() == "pt";

        public static string Title(HowCard c, string lang) => IsPt(lang) && c.TitlePt.Length > 0 ? c.TitlePt : c.TitleEn;

        public static string Pick(HowRow r, string lang) => IsPt(lang) && r.Pt.Length > 0 ? r.Pt : r.En;

        /// <summary>The rows to draw: the id and the text, in Rows order, only the ones the card has.</summary>
        public static List<KeyValuePair<string, string>> RowsOf(HowCard c, string lang)
        {
            var o = new List<KeyValuePair<string, string>>();
            foreach (var id in Rows)
                foreach (var r in c.Rows)
                    if (r.Id == id) { o.Add(new KeyValuePair<string, string>(id, Pick(r, lang))); break; }
            return o;
        }

        /// <summary>The heading of a row (the English text; the window shows it through Loc.T).</summary>
        public static string Heading(string id)
        {
            switch (id)
            {
                case "what": return "What it is";
                case "who": return "Who is it for";
                case "levels": return "Monster levels";
                case "drops": return "What drops";
                case "death": return "If you die";
                default: return "How often";
            }
        }

        /// <summary>A character key for the settings: letters and digits, the rest an underscore.</summary>
        public static string CharKey(string name)
        {
            var sb = new System.Text.StringBuilder();
            foreach (char c in name ?? "") sb.Append(char.IsLetterOrDigit(c) && c < 128 ? c : '_');
            return sb.Length > 0 ? sb.ToString() : "_";
        }

        /// <summary>True, and marked, the first time a character opens the card.</summary>
        public static bool FirstOpen(Dictionary<string, HashSet<string>> seen, string charKey, string key)
        {
            if (seen == null || key == null) return false;
            HashSet<string> set;
            if (!seen.TryGetValue(charKey ?? "_", out set)) seen[charKey ?? "_"] = set = new HashSet<string>();
            return set.Add(key);
        }
    }
}
