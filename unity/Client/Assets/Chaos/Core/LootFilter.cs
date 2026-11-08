// The loot filter and the loot channel. A port of game_lootfilter/lootfilterlogic.lua (the rules the client uses to draw; the server stays the
// authority for autoloot and click-to-loot) and of the protocol of lootfilter.lua. Server: data/scripts/chaos/lootfilter.lua, lootfilter_core.lua.
//
// Extended opcode 238 (JSON {action, data}):
//   client -> server  open | sync | set {s = settings} | preset {name} | take {k, n, id, one} | sound {s} | reset {scope, rule}
//   server -> client  settings {s, unlocked, presets = [{key, name, desc}], open, snd, counts}
//                     kill {k, m (monster), items = [{n, id, c, r, u, o, g, x, nm, left}], hits, counts}   update {k, left = [..]}
//                     decay {k}   msg {text}   counts {session, total}   peek {cid, items}   beam {..}
// The loot channel is the list of kills with their items; a click on an item takes it (Shift: one). Peek (client -> server {cid}) gives the
// rarity rows of an open bag: LootPeek, drawn as glow, frame and dim on the container slots. Not ported: beams, rule sounds (the sound
// settings are kept and sent back untouched).
// Tests: Core.Tests/HelperTests.cs (mirrors lootfilter_test.lua).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>What the server says about one item: rarity (0 or an id 1 2 3 4 5 10), unique, orb, category, name, count, best modifier tier, power.</summary>
    public struct LootInfo
    {
        public int R, T, C, S, Id, Left, N;
        public bool U, O, Pw;
        public string G, Nm, X;
        public bool HasLeft;

        static bool Flag(object o, string key)
        {
            var v = Json.Get(o, key);
            return v is bool b ? b : v is double d && d == 1 || v is string s && s == "1";
        }

        public static LootInfo From(object row)
        {
            return new LootInfo
            {
                R = Json.Int(row, "r"), T = Json.Int(row, "t"), C = Json.Int(row, "c", 1), S = Json.Int(row, "s"), Id = Json.Int(row, "id"), N = Json.Int(row, "n"),
                U = Flag(row, "u"), O = Flag(row, "o"), Pw = Flag(row, "pw"), G = Json.Text(row, "g", "other"), Nm = Json.Text(row, "nm", "item"), X = Json.Text(row, "x", ""),
                HasLeft = Json.Get(row, "left") is double, Left = Json.Int(row, "left"),
            };
        }
    }

    public sealed class LootFilterSettings
    {
        public int Highlight = 3, Dim, LootMin, LootFrom, Tier;
        public readonly Dictionary<string, bool> Show = new Dictionary<string, bool> { { "equipment", true }, { "currency", true }, { "supplies", true }, { "other", true } };
        public bool Icons = true, Notify = true;

        public LootFilterSettings Copy()
        {
            var c = new LootFilterSettings { Highlight = Highlight, Dim = Dim, LootMin = LootMin, LootFrom = LootFrom, Tier = Tier, Icons = Icons, Notify = Notify };
            foreach (var k in LootFilterRules.Categories) c.Show[k] = Show[k];
            return c;
        }

        /// <summary>The wire form of `set`: the same fields the server sanitises.</summary>
        public Dictionary<string, object> ToDict()
        {
            var show = new Dictionary<string, object>();
            foreach (var k in LootFilterRules.Categories) show[k] = Show[k];
            return new Dictionary<string, object> { { "highlight", Highlight }, { "dim", Dim }, { "lootMin", LootMin }, { "lootFrom", LootFrom }, { "show", show }, { "icons", Icons }, { "notify", Notify }, { "tier", Tier } };
        }
    }

    public static class LootFilterRules
    {
        public const int MaxRarity = 10, MaxTier = 8;
        public static readonly int[] RarityIds = { 1, 2, 3, 4, 5, 10 };
        public static readonly string[] Categories = { "equipment", "currency", "supplies", "other" };
        public const string UniqueColor = "#e07b24", OrbColor = "#4fd8d0";

        // the seven rarities (server/data/lib/chaos_rarity.lua); an item saved before them may carry 6 .. 9 (Legendary) or 11 .. 15 (Divine)
        static string NameOf(int id)
        {
            switch (id)
            {
                case 1: return "Common";
                case 2: return "Uncommon";
                case 3: return "Magic";
                case 4: return "Rare";
                case 5: case 6: case 7: case 8: case 9: return "Legendary";
                case 10: case 11: case 12: case 13: case 14: case 15: return "Divine";
                default: return null;
            }
        }

        static string ColorOfName(string name)
        {
            switch (name)
            {
                case "Common": return "#c8c8c8";
                case "Uncommon": return "#5ccf5c";
                case "Magic": return "#4a90ff";
                case "Rare": return "#a35cf0";
                case "Legendary": return "#ffd040";
                case "Divine": return "#c8e8ff";
                default: return null;
            }
        }

        /// <summary>The id of today's rarity for any id (0 stays 0, an id above 15 is the highest).</summary>
        public static int Canon(double id)
        {
            int n = (int)Math.Floor(double.IsNaN(id) ? 0 : id);
            if (n <= 0) return 0;
            if (n > 15) return MaxRarity;
            string name = NameOf(n);
            foreach (int c in RarityIds) if (NameOf(c) == name) return c;
            return 0;
        }

        public static LootFilterSettings Normalize(object s)
        {
            var o = new LootFilterSettings();
            if (!(s is Dictionary<string, object>)) return o;
            o.Highlight = Json.Get(s, "highlight") is double h ? Canon(Math.Max(0, h)) : o.Highlight;
            o.Dim = Json.Get(s, "dim") is double d ? Canon(Math.Max(0, d)) : o.Dim;
            o.LootMin = Json.Get(s, "lootMin") is double lm ? Canon(Math.Max(0, lm)) : o.LootMin;
            o.LootFrom = Json.Get(s, "lootFrom") is double lf ? Canon(Math.Max(0, lf)) : o.LootFrom;
            var show = Json.Get(s, "show");
            foreach (var c in Categories) o.Show[c] = !(Json.Get(show, c) is bool b && !b);
            o.Icons = !(Json.Get(s, "icons") is bool i && !i);
            o.Notify = !(Json.Get(s, "notify") is bool n && !n);
            o.Tier = Json.Get(s, "tier") is double t && !double.IsNaN(t) ? Math.Max(0, Math.Min(MaxTier, (int)Math.Floor(t))) : o.Tier;
            return o;
        }

        /// <summary>highlight (a unique, an orb, a rarity or modifier tier at the thresholds), normal or dim.</summary>
        public static string Classify(LootInfo info, LootFilterSettings s)
        {
            if (info.U || info.O) return "highlight";
            string category = string.IsNullOrEmpty(info.G) ? "other" : info.G;
            bool shown;
            if (!s.Show.TryGetValue(category, out shown)) shown = true;
            if (category == "equipment")
            {
                int r = Canon(info.R);
                if (s.Highlight > 0 && r >= s.Highlight) return "highlight";
                if (s.Tier > 0 && info.T >= s.Tier) return "highlight";
                if (!shown || r < s.Dim) return "dim";
                return "normal";
            }
            return shown ? "normal" : "dim";
        }

        /// <summary>The colour of an item's name (hex), null for a plain item.</summary>
        public static string Color(LootInfo info)
        {
            if (info.U) return UniqueColor;
            string name = NameOf(info.R);
            if (name != null) return ColorOfName(name);
            if (info.O) return OrbColor;
            return null;
        }

        public static string RarityName(int r)
        {
            string n = NameOf(r);
            return n == null ? null : Loc.T(n);
        }

        /// <summary>"[Rare] Name", "[Unique] Name" or the name.</summary>
        public static string Label(LootInfo info)
        {
            string name = info.Nm;
            if (info.U) return "[" + Loc.T("Unique") + "] " + name;
            string r = RarityName(info.R);
            return r != null ? "[" + r + "] " + name : name;
        }

        /// <summary>The threshold text of a rarity: "Rare+", "Off" for 0.</summary>
        public static string ThresholdText(int v)
        {
            string n = RarityName(v);
            return n == null ? Loc.T("Off") : n + "+";
        }

        public static string CategoryName(string c)
        {
            switch (c)
            {
                case "equipment": return Loc.T("Equipment");
                case "currency": return Loc.T("Currency (orbs, coins)");
                case "supplies": return Loc.T("Supplies (potions, runes)");
                default: return Loc.T("Other");
            }
        }

        /// <summary>The count an item icon shows (what is left in the corpse, the dropped count once all of it is gone) and whether it is gone.</summary>
        public static int IconCount(LootInfo info, out bool gone)
        {
            int left = info.HasLeft ? info.Left : info.C;
            gone = left <= 0;
            return left > 0 ? left : info.C;
        }

        /// <summary>The tooltip of a loot item.</summary>
        public static string Tooltip(LootInfo info)
        {
            var lines = new List<string> { (info.C > 1 ? info.C + "x " : "") + Label(info) };
            if (!string.IsNullOrEmpty(info.X)) lines.Add(info.X);
            if (info.HasLeft && info.Left <= 0) lines.Add(Loc.T("Looted (or gone)"));
            else
            {
                if (info.HasLeft && info.Left < info.C) lines.Add(Loc.T("{0} left in the corpse", info.Left));
                lines.Add(info.C > 1 ? Loc.T("Click: loot all   Shift+click: loot one") : Loc.T("Click: loot"));
            }
            return string.Join("\n", lines);
        }
    }

    /// <summary>The rows peek gave for one open container: index (the server's slot index) to row.</summary>
    public sealed class PeekSet
    {
        public bool Corpse;
        public readonly Dictionary<int, LootInfo> Items = new Dictionary<int, LootInfo>();
    }

    /// <summary>How a container slot is decorated by the loot filter (lootfilter.lua decorate).</summary>
    public struct PeekDecor
    {
        /// <summary>"highlight", "normal" or "dim".</summary>
        public string State;
        /// <summary>The rarity colour, null when the row has none.</summary>
        public string Color;
        public bool Glow, Soft, Dim;
    }

    public static class LootPeek
    {
        public const double DelaySeconds = 0.06;

        /// <summary>A row belongs to the item in the slot: the same client id and, with item attributes, the same rarity and unique flag.</summary>
        public static bool RowFits(LootInfo row, Item item, bool hasRow, bool attrsOn)
        {
            if (!hasRow || item == null || row.Id != item.Id) return false;
            if (!attrsOn) return true;
            if (LootFilterRules.Canon(row.R) != ItemRarity.Of(item)) return false;
            return row.U == ItemRarity.IsUnique(item);
        }

        /// <summary>An orb glows as a thin ring only, no frame on top.</summary>
        public static bool IsSoft(LootInfo info) => info.O && !info.U && LootFilterRules.Color(info) == LootFilterRules.OrbColor;

        public static PeekDecor Decorate(LootInfo row, bool corpse, LootFilterSettings s)
        {
            string state = LootFilterRules.Classify(row, s);
            string color = LootFilterRules.Color(row);
            bool lit = color != null && state == "highlight";
            bool soft = IsSoft(row);
            return new PeekDecor { State = state, Color = color, Glow = lit && !soft, Soft = lit && soft, Dim = corpse && state == "dim" };
        }

        /// <summary>The signature of a container's contents; peek is asked again when it changes.</summary>
        public static string Signature(Container c)
        {
            var sb = new System.Text.StringBuilder();
            sb.Append(c.Id).Append(':').Append(c.ItemId).Append(':').Append(c.FirstIndex).Append(':').Append(c.Items.Count);
            foreach (var it in c.Items) sb.Append(',').Append(it != null ? it.Id : 0).Append('x').Append(it != null ? it.Count : 0);
            return sb.ToString();
        }
    }

    /// <summary>The rules the server counts (lootfilter_core.lua F.RULES) and the sounds it can pick (F.SOUNDS).</summary>
    public static class LootRules
    {
        public struct Rule { public string Key, Name, Color; }
        public static readonly Rule[] All =
        {
            new Rule { Key = "unique", Name = "Uniques", Color = "#e07b24" },
            new Rule { Key = "power", Name = "Legendary powers", Color = "#ffd040" },
            new Rule { Key = "rarity", Name = "Rarity glow", Color = "#a35cf0" },
            new Rule { Key = "tier", Name = "Modifier tier", Color = "#4a90ff" },
            new Rule { Key = "orb", Name = "Orbs", Color = "#4fd8d0" },
        };
        public static readonly string[] Sounds = { "Chime", "Bell", "Ping", "Drum", "Fanfare" };

        public static string SoundName(int id) => id >= 1 && id <= Sounds.Length ? Loc.T(Sounds[id - 1]) : Loc.T("No sound");

        /// <summary>1234567 to "1,234,567".</summary>
        public static string Number(long n) => n.ToString("N0", System.Globalization.CultureInfo.InvariantCulture);

        public static Dictionary<string, int> Counts(object c)
        {
            var o = new Dictionary<string, int>();
            foreach (var r in All) { double v = Json.Number(c, r.Key); o[r.Key] = v > 0 ? (int)Math.Floor(v) : 0; }
            return o;
        }
    }

    /// <summary>The sound settings the server keeps per character (snd): a sound id per rule, volume, mute, show in the hunt tracker.</summary>
    public sealed class LootSoundSettings
    {
        public readonly Dictionary<string, int> Rules = new Dictionary<string, int> { { "unique", 5 }, { "power", 1 }, { "rarity", 0 }, { "tier", 0 }, { "orb", 0 } };
        public int Volume = 70;
        public bool Mute, Hunt = true;

        public LootSoundSettings Copy()
        {
            var c = new LootSoundSettings { Volume = Volume, Mute = Mute, Hunt = Hunt };
            foreach (var r in LootRules.All) c.Rules[r.Key] = Rules[r.Key];
            return c;
        }

        public static LootSoundSettings Normalize(object t)
        {
            var o = new LootSoundSettings();
            if (!(t is Dictionary<string, object>)) return o;
            o.Mute = Json.Bool(t, "mute");
            o.Hunt = !(Json.Get(t, "hunt") is bool h && !h);
            var rules = Json.Get(t, "rules");
            foreach (var r in LootRules.All)
            {
                if (!(Json.Get(rules, r.Key) is double v) || double.IsNaN(v)) continue;
                int id = (int)Math.Floor(v);
                o.Rules[r.Key] = id >= 0 && id <= LootRules.Sounds.Length ? id : 0;
            }
            if (Json.Get(t, "vol") is double vol && !double.IsNaN(vol)) o.Volume = Math.Max(0, Math.Min(100, (int)Math.Floor(vol)));
            return o;
        }

        public Dictionary<string, object> ToDict()
        {
            var rules = new Dictionary<string, object>();
            foreach (var r in LootRules.All) rules[r.Key] = Rules[r.Key];
            return new Dictionary<string, object> { { "rules", rules }, { "vol", Volume }, { "mute", Mute }, { "hunt", Hunt } };
        }

        public bool Same(LootSoundSettings b)
        {
            if (Volume != b.Volume || Mute != b.Mute || Hunt != b.Hunt) return false;
            foreach (var r in LootRules.All) if (Rules[r.Key] != b.Rules[r.Key]) return false;
            return true;
        }
    }

    /// <summary>The preview rows of the Filter tab: sample items and what the settings do to them.</summary>
    public static class LootPreview
    {
        public struct Entry { public string Text, State, Color; }

        public static List<Entry> Build(LootFilterSettings s)
        {
            var rows = new List<LootInfo>();
            rows.Add(new LootInfo { G = "equipment", Nm = Loc.T("Gear without rarity") });
            foreach (int id in LootFilterRules.RarityIds) rows.Add(new LootInfo { G = "equipment", R = id, Nm = Loc.T("{0} gear", LootFilterRules.RarityName(id)) });
            if (s.Tier > 0) rows.Add(new LootInfo { G = "equipment", R = 1, T = s.Tier, Nm = Loc.T("Common gear with a T{0} modifier", s.Tier) });
            rows.Add(new LootInfo { G = "equipment", U = true, Nm = Loc.T("A unique") });
            rows.Add(new LootInfo { G = "currency", O = true, Nm = Loc.T("An orb") });
            rows.Add(new LootInfo { G = "currency", Nm = Loc.T("Coins") });
            rows.Add(new LootInfo { G = "supplies", Nm = Loc.T("A potion") });
            rows.Add(new LootInfo { G = "other", Nm = Loc.T("Other loot") });
            var o = new List<Entry>();
            foreach (var r in rows)
            {
                string st = LootFilterRules.Classify(r, s);
                string word = st == "highlight" ? Loc.T("glows") : st == "dim" ? Loc.T("dimmed") : Loc.T("shown");
                o.Add(new Entry { Text = r.Nm + ": " + word, State = st, Color = LootFilterRules.Color(r) });
            }
            return o;
        }
    }

    public sealed class LootKill
    {
        public int K;
        public string Monster = "";
        public double At;
        public bool Decayed;
        public readonly List<LootInfo> Items = new List<LootInfo>();
    }

    public sealed class LootFilterModel
    {
        public const byte Opcode = 238;
        public const int MaxKills = 40;

        readonly ExtOpcodes ext;
        public Func<double> Clock = () => 0;
        public LootFilterSettings Settings = new LootFilterSettings();
        public bool Loaded, Unlocked;
        public readonly List<KeyValuePair<string, string>> Presets = new List<KeyValuePair<string, string>>();
        /// <summary>The kills, newest first.</summary>
        public readonly List<LootKill> Kills = new List<LootKill>();
        /// <summary>The server's refusal of a click (shown next to the channel).</summary>
        public string Message = "";
        public double MessageAt = -1e9;
        public event Action Changed = delegate { };
        /// <summary>The server's rule counters (counts {session, total}) and the sound settings (snd).</summary>
        public Dictionary<string, int> CountSession = LootRules.Counts(null), CountTotal = LootRules.Counts(null);
        public LootSoundSettings Sound = new LootSoundSettings();
        /// <summary>Kills since the login that matched a rule: the last kill's hits, for a sound when one plays.</summary>
        public Dictionary<string, int> LastHits = new Dictionary<string, int>();
        public void SetSound(LootSoundSettings s) { Sound = s.Copy(); ext.Send(Opcode, "sound", new Dictionary<string, object> { { "s", s.ToDict() } }); Changed(); }
        /// <summary>Reset the counters: scope session, total or all (one rule).</summary>
        public void ResetCounts(string scope, string rule = null)
        {
            var d = new Dictionary<string, object> { { "scope", scope } };
            if (rule != null) d["rule"] = rule;
            ext.Send(Opcode, "reset", d);
        }
        void ReadCounts(object c)
        {
            if (!(c is Dictionary<string, object>)) return;
            CountSession = LootRules.Counts(Json.Get(c, "session")); CountTotal = LootRules.Counts(Json.Get(c, "total"));
        }
        /// <summary>The peek rows of the open containers, by container id.</summary>
        public readonly Dictionary<int, PeekSet> Peeks = new Dictionary<int, PeekSet>();
        /// <summary>Asks for the rarity rows of an open container.</summary>
        public void RequestPeek(int cid) { ext.Send(Opcode, "peek", new Dictionary<string, object> { { "cid", cid } }); }
        public void ForgetPeek(int cid) { Peeks.Remove(cid); }
        public PeekSet PeekOf(int cid) { PeekSet p; return Peeks.TryGetValue(cid, out p) ? p : null; }
        /// <summary>The server answered "open": show the settings.</summary>
        public event Action ShowRequested = delegate { };

        public LootFilterModel(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        public void Sync() { ext.Send(Opcode, "sync", null); }
        public void Open() { ext.Send(Opcode, "open", null); }
        public void Set(LootFilterSettings s) { Settings = s.Copy(); ext.Send(Opcode, "set", new Dictionary<string, object> { { "s", s.ToDict() } }); Changed(); }
        public void Preset(string key) { ext.Send(Opcode, "preset", new Dictionary<string, object> { { "name", key } }); }

        /// <summary>Click on a loot item: take it (one: only one of a stack).</summary>
        public void Take(LootKill kill, LootInfo item, bool one)
        {
            ext.Send(Opcode, "take", new Dictionary<string, object> { { "k", kill.K }, { "n", item.N }, { "id", item.Id }, { "one", one } });
        }

        LootKill Find(int k) { foreach (var x in Kills) if (x.K == k) return x; return null; }

        void OnMessage(ExtMessage m)
        {
            var d = m.Data;
            switch (m.Action)
            {
                case "settings":
                {
                    Settings = LootFilterRules.Normalize(Json.Get(d, "s"));
                    Unlocked = Json.Bool(d, "unlocked");
                    Presets.Clear();
                    foreach (object p in Json.List(d, "presets")) Presets.Add(new KeyValuePair<string, string>(Json.Text(p, "key"), Json.Text(p, "name")));
                    if (Json.Get(d, "snd") is Dictionary<string, object>) Sound = LootSoundSettings.Normalize(Json.Get(d, "snd"));
                    ReadCounts(Json.Get(d, "counts"));
                    Loaded = true;
                    Changed();
                    if (Json.Bool(d, "open")) ShowRequested();
                    return;
                }
                case "kill":
                {
                    int k = Json.Int(d, "k", -1);
                    if (k < 0) return;
                    var kill = new LootKill { K = k, Monster = Json.Text(d, "m", ""), At = Clock() };
                    foreach (object row in Json.List(d, "items"))
                    {
                        var info = LootInfo.From(row);
                        if (info.N == 0) info.N = kill.Items.Count + 1;
                        kill.Items.Add(info);
                    }
                    ReadCounts(Json.Get(d, "counts"));
                    LastHits = Json.Get(d, "hits") is Dictionary<string, object> ? LootRules.Counts(Json.Get(d, "hits")) : new Dictionary<string, int>();
                    Kills.Insert(0, kill);
                    while (Kills.Count > MaxKills) Kills.RemoveAt(Kills.Count - 1);
                    Changed();
                    return;
                }
                case "update":
                {
                    var kill = Find(Json.Int(d, "k", -1));
                    if (kill == null) return;
                    var left = Json.List(d, "left");
                    for (int i = 0; i < kill.Items.Count && i < left.Count; i++)
                    {
                        var it = kill.Items[i];
                        it.HasLeft = left[i] is double; it.Left = left[i] is double l ? (int)l : 0;
                        kill.Items[i] = it;
                    }
                    Changed();
                    return;
                }
                case "decay":
                {
                    var kill = Find(Json.Int(d, "k", -1));
                    if (kill != null) { kill.Decayed = true; Changed(); }
                    return;
                }
                case "counts": ReadCounts(d); Changed(); return;
                case "peek":
                {
                    int cid = Json.Int(d, "cid", -1);
                    if (cid < 0) return;
                    var set = new PeekSet { Corpse = Json.Bool(d, "corpse") };
                    foreach (object row in Json.List(d, "items"))
                    {
                        int idx = Json.Int(row, "i", -1);
                        if (idx >= 0) set.Items[idx] = LootInfo.From(row);
                    }
                    Peeks[cid] = set;
                    Changed();
                    return;
                }
                case "msg":
                    Message = Json.Text(d, "text", ""); MessageAt = Clock();
                    Changed();
                    return;
            }
        }

        public void Reset() { Peeks.Clear(); CountSession = LootRules.Counts(null); CountTotal = LootRules.Counts(null); Sound = new LootSoundSettings(); LastHits.Clear(); Kills.Clear(); Loaded = false; Message = ""; Presets.Clear(); Settings = new LootFilterSettings(); }
    }
}
