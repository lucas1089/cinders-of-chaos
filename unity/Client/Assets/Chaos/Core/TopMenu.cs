// The top menu (client client_chaos_topbar): category buttons with drop-downs, entries sorted by their shown text, systems opened by
// level. The server (unlocks.lua, extended opcode 115) sends `state` {entries [{key, level, menu}], unlocked [key], seen [key],
// next {key, level}, all} and `new` {key, level, menu, title, why [line1, line2]}; the client sends `hello` and `seen {key}`.
// An entry the table does not name is open. The next one to unlock shows grey with its level; later ones are hidden. This file is the
// pure part: the entries (Unity windows by class name, Info pages, actions), the unlock state, the sort key.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>An entry of the menu. Target: "win:ClassName" (a Unity window), "info:page" (Info and Services), "act:name" (logout).</summary>
    public sealed class MenuEntry
    {
        public string Text = "", Target = "";
        public MenuEntry[] Sub;
        public bool Separator;
    }

    public sealed class MenuCategory
    {
        public string Id = "", Text = "";
        public MenuEntry[] Entries = new MenuEntry[0];
    }

    public static class TopMenu
    {
        static MenuEntry E(string text, string target) => new MenuEntry { Text = text, Target = target };

        public const string WindowsId = "windows";

        /// <summary>The menu's categories, from the main client's CATEGORIES with the entries that have a Unity window. Windows that no
        /// entry names are added by the app under "Windows", so nothing becomes unreachable.</summary>
        public static readonly MenuCategory[] Categories =
        {
            new MenuCategory { Id = "character", Text = Lk.N("Character"), Entries = new[]
            {
                E("Skills", "win:SkillsWindow"), E("Spellbook", "win:SpellbookWindow"), E("Passive Tree", "win:PassiveTreeWindow"),
                E("Character Info", "info:character"), E("Services", "info:services"),
                E("Inventory", "win:EquipmentWindow"), E("Containers", "win:ContainersWindow"),
                E("Achievements", "win:AchievementsWindow"), E("Pets", "win:PetsWindow"), E("Transmog", "win:TransmogWindow"), E("Cosmetics", "win:CosmeticsWindow"),
                E("Charms", "win:CharmsWindow"),
                E("Spell Supports", "win:SpellSupportsWindow"), E("Chaos Pact", "win:PactWindow"), E("Loadouts", "win:LoadoutsWindow"),
                E("Town Portal", "win:TownPortalWindow"), E("Hideout", "win:HideoutWindow"),
            } },
            new MenuCategory { Id = "hunt", Text = Lk.N("Hunt"), Entries = new[]
            {
                E("Battle List", "win:BattleListWindow"), E("Party Frames", "win:PartyFramesWindow"), E("Hunt Tracker", "win:HuntWindow"), E("DPS Meter", "win:DpsMeterWindow"),
                E("Minimap", "win:MinimapWindow"), E("Fight", "win:FightWindow"),
                E("Bestiary", "win:BestiaryWindow"),
                E("Map Overlay", "win:MapOverlayWindow"), E("Map Markers", "win:MapMarkersWindow"), E("Auto Loot", "win:AutoLootWindow"),
            } },
            new MenuCategory { Id = "adventure", Text = Lk.N("Adventure"), Entries = new[]
            {
                E("Next Goals", "win:GoalsWindow"), E("Goal Tracker", "win:GoalTrackerWindow"), E("Rifts", "info:rift"), E("Events", "info:events"),
                E("Group Queue", "win:GroupQueueWindow"),
                // endgame activities (track L); the menu texts are the keys of the server's level unlocks (unlocks_config.lua)
                E("Dungeons", "win:DungeonsWindow"), E("Infinity Tower", "win:TowerWindow"), E("Bounty Board", "win:BountyWindow"),
                E("Arena", "win:ArenaWindow"), E("Guild Siege", "win:SiegeWindow"), E("Ember Descent", "win:DescentWindow"),
                E("Rift Atlas", "win:RiftAtlasWindow"), E("Waystone Atlas", "win:WaystoneAtlasWindow"), E("Raid: Ashen Sepulchre", "win:RaidWindow"),
                E("Scorched Marches", "win:PvpZoneWindow"), E("Battleground", "win:BattlegroundWindow"), E("Invasions", "win:InvasionWindow"),
                E("Daily Reward", "win:DailyWindow"), E("Season", "win:SeasonWindow"), E("Season Pass", "win:PassWindow"), E("Weekly Chest", "win:WeeklyChestWindow"),
                E("Ember Cache", "win:EmberCacheWindow"),
            } },
            new MenuCategory { Id = "economy", Text = Lk.N("Economy"), Entries = new[]
            {
                E("House", "info:house"), E("Ancestral Store", "info:ancestral"),
                E("Market", "win:MarketWindow"),
                E("Crafting Bench", "win:CraftingWindow"), E("Professions", "win:ProfessionsWindow"), E("Crafting Tables", "win:CraftTableWindow"),
                E("Codex", "win:CodexWindow"), E("Item Finder", "win:ItemFinderWindow"), E("Orb Exchange", "win:OrbExchangeWindow"), E("Candlemarks", "win:CandlemarksWindow"), E("Auto Seller", "win:AutoSellerWindow"),
            } },
            new MenuCategory { Id = "social", Text = Lk.N("Social"), Entries = new[]
            {
                E("Channels", "win:ChannelsWindow"),
                E("Guild", "win:GuildWindow"), E("Guild Wars", "win:GuildWarWindow"), E("Party Finder", "win:PartyFinderWindow"),
                E("Leaderboards", "win:LeaderboardWindow"), E("Inspect Player", "win:InspectWindow"),
            } },
            new MenuCategory { Id = "system", Text = Lk.N("System"), Entries = new[]
            {
                E("Hotkeys", "win:HotkeyBarWindow"), E("Help Search", "win:HelpSearchWindow"), E("Server Info", "info:server"),
            } },
        };

        const string Accented = "\u00e1\u00e0\u00e2\u00e3\u00e4\u00e9\u00ea\u00e8\u00eb\u00ed\u00ec\u00ee\u00ef\u00f3\u00f2\u00f4\u00f5\u00f6\u00fa\u00f9\u00fb\u00fc\u00e7\u00f1";
        const string Plain = "aaaaaeeeeiiiiooooouuuucn";

        /// <summary>The sort key of a shown text: lower case, accents folded, leading spaces and marks dropped.</summary>
        public static string SortKey(string text)
        {
            var sb = new StringBuilder();
            foreach (char c in (text ?? "").ToLowerInvariant())
            {
                int i = Accented.IndexOf(c);
                sb.Append(i >= 0 ? Plain[i] : c);
            }
            string s = sb.ToString();
            int k = 0;
            while (k < s.Length && (char.IsWhiteSpace(s[k]) || char.IsPunctuation(s[k]) || char.IsSymbol(s[k]))) k++;
            return s.Substring(k);
        }

        /// <summary>The entries of a list in alphabetical order of their shown text (a stable sort; separators stay between groups).</summary>
        public static List<MenuEntry> Sorted(IList<MenuEntry> list, Func<MenuEntry, string> textOf)
        {
            var output = new List<MenuEntry>();
            var group = new List<KeyValuePair<MenuEntry, int>>();
            Action flush = () =>
            {
                var plain = new List<KeyValuePair<MenuEntry, int>>();
                var subs = new List<KeyValuePair<MenuEntry, int>>();
                foreach (var g in group) (g.Key.Sub != null ? subs : plain).Add(g);
                Comparison<KeyValuePair<MenuEntry, int>> cmp = (a, b) =>
                {
                    int c = string.CompareOrdinal(SortKey(textOf(a.Key)), SortKey(textOf(b.Key)));
                    return c != 0 ? c : a.Value.CompareTo(b.Value);
                };
                plain.Sort(cmp); subs.Sort(cmp);
                foreach (var p in plain) output.Add(p.Key);
                foreach (var p in subs) output.Add(p.Key);
                group.Clear();
            };
            int n = 0;
            foreach (var e in list)
            {
                if (e.Separator) { flush(); output.Add(e); }
                else group.Add(new KeyValuePair<MenuEntry, int>(e, n++));
            }
            flush();
            return output;
        }
    }

    public sealed class UnlockEntry { public string Key = "", Menu = ""; public int Level; }

    public sealed class UnlockAnnouncement { public string Key = "", Menu = "", Title = "", Line1 = "", Line2 = ""; public int Level; }

    public enum MenuStatus { Open, Locked, Hidden }

    /// <summary>The level-gated menu state of opcode 115 (the main client's topbarunlockslogic.lua).</summary>
    public sealed class MenuUnlocks
    {
        public const byte Opcode = 115;
        public const int WindowSeconds = 30;
        public const double TextMs = 4200;
        readonly ExtOpcodes ext;
        /// <summary>False until the server's state came: the menu is whole (an older server, a login in progress).</summary>
        public bool Loaded, All;
        public bool ShowAll;
        public readonly Dictionary<string, UnlockEntry> Entries = new Dictionary<string, UnlockEntry>();
        public readonly Dictionary<string, UnlockEntry> ByMenu = new Dictionary<string, UnlockEntry>();
        public readonly HashSet<string> Unlocked = new HashSet<string>(), Seen = new HashSet<string>();
        public string NextKey = "";
        public int NextLevel;
        /// <summary>The last `new` message and when it came (session ms), for the screen text and the Go window.</summary>
        public UnlockAnnouncement Announcement;
        public double AnnouncedAt;
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };

        public MenuUnlocks(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Hello() { ext.Send(Opcode, "hello", new Dictionary<string, object>()); }

        public void Handle(string action, object data)
        {
            if (action == "state") Apply(data);
            else if (action == "new")
            {
                var a = Announce(data);
                if (a == null) return;
                MarkUnlocked(a.Key);
                Announcement = a;
                AnnouncedAt = Clock();
                Changed();
            }
        }

        public void Apply(object data)
        {
            if (!(data is Dictionary<string, object>)) return;
            Entries.Clear(); ByMenu.Clear(); Unlocked.Clear(); Seen.Clear();
            foreach (object o in Json.List(data, "entries"))
            {
                string key = Json.Text(o, "key"), menu = Json.Text(o, "menu");
                if (key.Length == 0 || menu.Length == 0) continue;
                var e = new UnlockEntry { Key = key, Menu = menu, Level = Json.Int(o, "level") };
                Entries[key] = e;
                ByMenu[menu] = e;
            }
            foreach (object k in Json.List(data, "unlocked")) if (k is string s) Unlocked.Add(s);
            foreach (object k in Json.List(data, "seen")) if (k is string s) Seen.Add(s);
            object nx = Json.Get(data, "next");
            NextKey = nx is Dictionary<string, object> ? Json.Text(nx, "key") : "";
            NextLevel = nx is Dictionary<string, object> ? Json.Int(nx, "level") : 0;
            All = Json.Bool(data, "all");
            Loaded = true;
            Changed();
        }

        public static UnlockAnnouncement Announce(object data)
        {
            if (!(data is Dictionary<string, object>) || Json.Text(data, "key").Length == 0 || Json.Text(data, "title").Length == 0) return null;
            var why = Json.List(data, "why");
            return new UnlockAnnouncement
            {
                Key = Json.Text(data, "key"), Menu = Json.Text(data, "menu"), Title = Json.Text(data, "title"), Level = Json.Int(data, "level"),
                Line1 = why.Count > 0 ? why[0] as string ?? "" : "", Line2 = why.Count > 1 ? why[1] as string ?? "" : "",
            };
        }

        public void MarkUnlocked(string key)
        {
            if (key.Length == 0) return;
            Unlocked.Add(key);
            Seen.Remove(key);
            if (NextKey == key) { NextKey = ""; NextLevel = 0; }
        }

        /// <summary>The player opened the entry with this menu text: the key to tell the server when a badge went away, else null.</summary>
        public string MarkSeen(string menu)
        {
            if (ByMenu.TryGetValue(menu, out var e) && Unlocked.Contains(e.Key) && Seen.Add(e.Key))
            {
                ext.Send(Opcode, "seen", new Dictionary<string, object> { { "key", e.Key } });
                return e.Key;
            }
            return null;
        }

        public MenuStatus Status(string menu, out int level)
        {
            level = 0;
            if (!Loaded || All || ShowAll) return MenuStatus.Open;
            if (!ByMenu.TryGetValue(menu, out var e) || Unlocked.Contains(e.Key)) return MenuStatus.Open;
            level = e.Level;
            return NextKey == e.Key ? MenuStatus.Locked : MenuStatus.Hidden;
        }

        public bool IsNew(string menu) => ByMenu.TryGetValue(menu, out var e) && Unlocked.Contains(e.Key) && !Seen.Contains(e.Key);

        /// <summary>The level an entry needs while the player cannot use it yet, else 0 (a hotkey says "Unlocks at level n").</summary>
        public int BlockedLevel(string menu)
        {
            var s = Status(menu, out int level);
            return s == MenuStatus.Open ? 0 : level;
        }

        public void Clear()
        {
            Entries.Clear(); ByMenu.Clear(); Unlocked.Clear(); Seen.Clear();
            NextKey = ""; NextLevel = 0; Loaded = false; All = false; Announcement = null;
        }
    }
}
