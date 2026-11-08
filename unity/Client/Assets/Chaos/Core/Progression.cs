// Progression systems of the main client, on the same server opcodes (all JSON {action, data}):
//   SkillStats   119  combat stat rows of the Skills window (client game_skillstats), plus the simple skill list (game_simpleskills)
//   Goals        178  Next Goals window and tracker (game_goals): goals, tracker, ascension, spellquest, welcome, done
//   HuntTracker  241  hunt session numbers (game_hunt): state, restockQuote
//   RiftHud      228  rift run HUD (game_rift): start, update, end, query
//   ChaosInfo    237  Info and Services pages (game_chaosinfo): catalog, result, services, store
// `Progression` owns one of each, built by the session. Every class keeps only what the server said; windows draw it.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>Marks an English text that the windows pass to Loc.T later (so the pt-BR check can find it).</summary>
    public static class Lk
    {
        public static string N(string text) => text;
    }

    /// <summary>The numbers every window of this file formats the same way as the main client's HuntMath and RiftMath.</summary>
    public static class Fmt
    {
        /// <summary>3725 -> "1h 02m 05s", 65 -> "1m 05s", 9 -> "9s".</summary>
        public static string Duration(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60, sec = s % 60;
            if (d > 0) return string.Format(CultureInfo.InvariantCulture, "{0}d {1:00}h {2:00}m", d, h, m);
            if (h > 0) return string.Format(CultureInfo.InvariantCulture, "{0}h {1:00}m {2:00}s", h, m, sec);
            if (m > 0) return string.Format(CultureInfo.InvariantCulture, "{0}m {1:00}s", m, sec);
            return sec + "s";
        }

        /// <summary>1234 -> "1.2k", 2500000 -> "2.5M"; keeps the sign.</summary>
        public static string Short(double n)
        {
            string sign = n < 0 ? "-" : "";
            n = Math.Abs(n);
            double[] limits = { 1e12, 1e9, 1e6, 1e3 };
            string[] units = { "T", "B", "M", "k" };
            for (int i = 0; i < limits.Length; i++)
                if (n >= limits[i])
                {
                    double v = Math.Floor(n / limits[i] * 10) / 10;
                    string text = v == Math.Floor(v) ? ((long)v).ToString(CultureInfo.InvariantCulture) : v.ToString("0.0", CultureInfo.InvariantCulture);
                    return sign + text + units[i];
                }
            return sign + ((long)Math.Floor(n)).ToString(CultureInfo.InvariantCulture);
        }

        /// <summary>1234567 -> "1,234,567".</summary>
        public static string Exact(double n) => ((long)Math.Floor(n)).ToString("N0", CultureInfo.InvariantCulture);

        /// <summary>75 -> "1:15".</summary>
        public static string Clock(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            return (s / 60).ToString(CultureInfo.InvariantCulture) + ":" + (s % 60).ToString("00", CultureInfo.InvariantCulture);
        }
    }

    // ================================================================================================ skills
    /// <summary>One row of the combat stats block: hidden, text, and whether it is above zero (green).</summary>
    public struct StatRow
    {
        public bool Visible;
        public string Text;
        public bool Green;
    }

    public sealed class SkillStats
    {
        public const byte Opcode = 119;
        readonly ExtOpcodes ext;
        /// <summary>The last stats message, null until one came (an older server never sends it).</summary>
        public object Last;
        public Action Changed = delegate { };

        public SkillStats(ExtOpcodes e) { ext = e; ext.On(Opcode, m => { if (m.Action == "stats" && m.Data is Dictionary<string, object>) { Last = m.Data; Changed(); } }); }

        public void Get() { ext.Send(Opcode, "get", new Dictionary<string, object>()); }
        public void Clear() { Last = null; }

        public static readonly string[] Rows = { "damage", "attack", "defense", "armor", "mitigation" };

        static bool Num(object v, out int n)
        {
            n = 0;
            if (v is double d && !double.IsNaN(d) && !double.IsInfinity(d)) { n = (int)Math.Floor(d + 0.5); return true; }
            return false;
        }

        /// <summary>The rows of the combat stat block (the main client's ChaosSkillStatsView.build): "-" before the server's numbers, the
        /// damage and attack rows hidden when the server sends none (a wand, bare hands), the mitigation as a percent.</summary>
        public static Dictionary<string, StatRow> Build(object data)
        {
            var o = new Dictionary<string, StatRow>();
            if (!(data is Dictionary<string, object>))
            {
                foreach (string r in Rows) o[r] = new StatRow { Visible = true, Text = "-" };
                return o;
            }
            Func<string, StatRow> number = key => Num(Json.Get(data, key), out int n)
                ? new StatRow { Visible = true, Text = Fmt.Short(n), Green = n > 0 } : new StatRow { Visible = true, Text = "-" };
            o["damage"] = Num(Json.Get(data, "damage"), out int dmg) && dmg > 0 ? number("damage") : new StatRow { Visible = false, Text = "-" };
            o["attack"] = Num(Json.Get(data, "attack"), out int atk) && atk > 0 ? number("attack") : new StatRow { Visible = false, Text = "-" };
            o["defense"] = number("defense");
            o["armor"] = number("armor");
            double share = Json.Get(data, "mitigation") is double m && !double.IsNaN(m) ? Math.Max(0, Math.Min(1, m)) : -1;
            o["mitigation"] = share < 0 ? new StatRow { Visible = true, Text = "-" }
                : new StatRow { Visible = true, Text = "+" + (share * 100).ToString("0.0", CultureInfo.InvariantCulture) + "%", Green = share > 0 };
            return o;
        }

        // ---- the simple skill list: Melee (best of sword, club, axe), Ranged, Magic / Wand, Shielding, Fist for the Monk line
        public const int Fist = 0, Club = 1, Sword = 2, Axe = 3, Distance = 4, Shielding = 5, Fishing = 6;

        /// <summary>The bar tooltip of a skill row ("Melee: 42" and the percent to the next level).</summary>
        public static string BarTip(string name, int level, int percent) => name + ": " + level + "\n" + Loc.T("{0}% to the next level", percent);

        /// <summary>The row tooltip of the Melee row: the three weapon skills are one.</summary>
        public static string MeleeTip() => Loc.T("Swords, axes and clubs share one skill: the best of the three.");

        /// <summary>A boosted skill (level above base) shows green, as in the main client.</summary>
        public static bool Boosted(SkillValue k) => k.Level > k.Base;

        public static bool ShowFist(int vocation) => vocation == 17 || vocation == 18 || vocation == 19;

        /// <summary>The best of sword, club and axe (a tie by the higher percent, then in the order sword, club, axe).</summary>
        public static SkillValue Melee(SkillValue[] skills)
        {
            int[] order = { Sword, Club, Axe };
            SkillValue best = default;
            bool have = false;
            foreach (int i in order)
            {
                if (i >= skills.Length) continue;
                var s = skills[i];
                if (!have || s.Level > best.Level || (s.Level == best.Level && s.Percent > best.Percent)) { best = s; have = true; }
            }
            return best;
        }
    }

    // ================================================================================================ goals
    public sealed class GoalWhere
    {
        public string K = "", M = "", F = "", Page = "", Label = "";
        public int Id;
        public bool HasPos;
        public int X, Y, Z;

        public static GoalWhere From(object o)
        {
            if (!(o is Dictionary<string, object>)) return null;
            var w = new GoalWhere { K = Json.Text(o, "k"), M = Json.Text(o, "m"), F = Json.Text(o, "f"), Page = Json.Text(o, "page"), Label = Json.Text(o, "label"), Id = Json.Int(o, "id") };
            object pos = Json.Get(o, "pos");
            if (pos is Dictionary<string, object> && Json.Get(pos, "x") is double && Json.Get(pos, "y") is double && Json.Get(pos, "z") is double)
            { w.HasPos = true; w.X = Json.Int(pos, "x"); w.Y = Json.Int(pos, "y"); w.Z = Json.Int(pos, "z"); }
            return w;
        }

        /// <summary>The button text, or null when the row has no action (the main client's V.whereButton).</summary>
        public string Button()
        {
            if (K == "window" || K == "info") return Lk.N("Open");
            if (K == "tasks") return Lk.N("Kill Tasks");
            if (K == "finder") return Lk.N("Item Finder");
            if (HasPos) return Lk.N("Show on map");
            if (K == "hunts") return Lk.N("Bestiary");
            return null;
        }
    }

    public sealed class GoalRow
    {
        public string Key = "", State = "open", Title = "", Why = "", Effort = "", Reward = "", Hint = "";
        public int Level, Progress, Target = 1;
        public GoalWhere Where;

        public static GoalRow From(object o)
        {
            if (!(o is Dictionary<string, object>)) return null;
            return new GoalRow
            {
                Key = Json.Text(o, "key"), State = Json.Text(o, "state", "open"), Title = Json.Text(o, "title", "?"), Why = Json.Text(o, "why"),
                Effort = Json.Text(o, "effort"), Reward = Json.Text(o, "reward"), Hint = Json.Text(o, "hint"), Level = Json.Int(o, "level"),
                Progress = Json.Int(o, "progress"), Target = Math.Max(1, Json.Int(o, "target", 1)), Where = GoalWhere.From(Json.Get(o, "where")),
            };
        }

        public int Percent => State == "done" ? 100 : State == "locked" ? 0 : Math.Min(100, Math.Max(0, Progress) * 100 / Target);
        public bool Done => State == "done" || Progress >= Target;

        /// <summary>The tracker text: the title and "n/m" when there are several steps, "Done" once finished (Loc key "Done").</summary>
        public string TrackerText(bool ascension)
        {
            int p = Math.Max(0, Math.Min(Target, Progress));
            if (ascension && (State == "done" || p >= Target)) return Title + "  " + Loc.T("Done");
            return Title + (Target == 1 ? "" : "  " + p + "/" + Target);
        }
    }

    public sealed class GoalHunt { public string Id = "", Name = ""; public int Lo, Hi; public GoalWhere Where; }

    public sealed class Goals
    {
        public const byte Opcode = 178;
        readonly ExtOpcodes ext;
        public bool HasHeader;
        public int Level, Done, Total, More, Next;
        public string NextName = "", BandName = "", BandText = "";
        public int BandFrom = 1, BandTo = -1, BandIndex = 1, BandCount = 1;
        public bool HasSeason;
        public readonly List<GoalRow> GoalList = new List<GoalRow>(), Upcoming = new List<GoalRow>(), Tracker = new List<GoalRow>(),
            Ascension = new List<GoalRow>(), SpellQuest = new List<GoalRow>(), Welcome = new List<GoalRow>();
        public readonly List<KeyValuePair<string, GoalWhere>> Gear = new List<KeyValuePair<string, GoalWhere>>();
        public readonly List<GoalHunt> Hunts = new List<GoalHunt>();
        public GoalWhere Here;
        public string WelcomeTitle = "";
        public int WelcomeStep, WelcomeCount;
        public string DoneText = "";
        public int DoneCount;
        public bool Watching;
        public Action Changed = delegate { };
        public Action<string> Notice = delegate { };

        public Goals(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Open() { Watching = true; ext.Send(Opcode, "open", new Dictionary<string, object>()); }
        public void Close() { Watching = false; ext.Send(Opcode, "close", new Dictionary<string, object>()); }
        public void RequestTracker() { ext.Send(Opcode, "tracker", new Dictionary<string, object>()); }
        public void SkipWelcome() { ext.Send(Opcode, "welcomeSkip", new Dictionary<string, object>()); }

        static void Fill(List<GoalRow> list, List<object> rows)
        {
            list.Clear();
            foreach (object o in rows) { var r = GoalRow.From(o); if (r != null) list.Add(r); }
        }

        public void Handle(string action, object data)
        {
            switch (action)
            {
                case "goals":
                {
                    object h = Json.Get(data, "header");
                    HasHeader = h is Dictionary<string, object>;
                    if (HasHeader)
                    {
                        Level = Json.Int(h, "level"); Done = Json.Int(h, "done"); Total = Json.Int(h, "total"); More = Json.Int(h, "more");
                        Next = Json.Int(h, "next"); NextName = Json.Text(h, "nextName"); HasSeason = Json.Get(h, "season") != null;
                        object b = Json.Get(h, "band");
                        if (b is Dictionary<string, object>)
                        {
                            BandName = Json.Text(b, "name"); BandText = Json.Text(b, "text"); BandFrom = Json.Int(b, "from", 1);
                            BandTo = Json.Get(b, "to") is double t ? (int)t : -1; BandIndex = Json.Int(b, "index", 1); BandCount = Math.Max(1, Json.Int(b, "count", 1));
                        }
                    }
                    Fill(GoalList, Json.List(data, "goals"));
                    Fill(Upcoming, Json.List(data, "upcoming"));
                    Gear.Clear();
                    foreach (object g in Json.List(data, "gear")) Gear.Add(new KeyValuePair<string, GoalWhere>(Json.Text(g, "text"), GoalWhere.From(Json.Get(g, "where"))));
                    Hunts.Clear();
                    foreach (object g in Json.List(data, "hunts"))
                        Hunts.Add(new GoalHunt { Id = Json.Text(g, "id"), Name = Json.Text(g, "name"), Lo = Json.Int(g, "lo"), Hi = Json.Int(g, "hi"), Where = GoalWhere.From(Json.Get(g, "where")) });
                    Here = GoalWhere.From(Json.Get(data, "hereWhere"));
                    break;
                }
                case "tracker": Fill(Tracker, Json.List(data, "rows")); break;
                case "ascension": Fill(Ascension, Json.List(data, "rows")); break;
                case "spellquest": Fill(SpellQuest, Json.List(data, "rows")); break;
                case "welcome":
                    Fill(Welcome, Json.List(data, "rows"));
                    WelcomeTitle = Json.Text(data, "title"); WelcomeStep = Json.Int(data, "step"); WelcomeCount = Json.Int(data, "count");
                    break;
                case "done":
                    DoneText = Json.Text(data, "text");
                    DoneCount++;
                    Notice(Loc.T("Goal done: {0}", DoneText));
                    break;
                default: return;
            }
            Changed();
        }

        public bool TrackerHasRows => Welcome.Count + Tracker.Count + Ascension.Count + SpellQuest.Count > 0;

        public int BandPercent => HasHeader ? BandIndex * 100 / Math.Max(1, BandCount) : 0;

        /// <summary>"Level 300-499: World bosses" / "Level 2000+: The apex".</summary>
        public string HeaderLine()
        {
            if (!HasHeader || BandName.Length == 0) return Loc.T("Next Goals");
            return BandTo >= 0 ? Loc.T("Level {0}-{1}: {2}", BandFrom, BandTo, BandName) : Loc.T("Level {0}+: {1}", BandFrom, BandName);
        }

        public string SummaryLine()
        {
            if (!HasHeader) return "";
            string s = Loc.T("Goals done: {0} / {1}", Done, Total);
            if (Next > 0) s += "   " + Loc.T("Next band at level {0}: {1}", Next, NextName);
            return s;
        }

        /// <summary>The state's label on the bar of a goal row: "Unlocks at level n", "Done", "Not yet" or "p / t".</summary>
        public static string BarLabel(GoalRow r)
        {
            if (r.State == "locked") return Loc.T("Unlocks at level {0}", r.Level);
            if (r.State == "done") return Loc.T("Done");
            return r.Target == 1 ? Loc.T("Not yet") : Math.Min(r.Target, Math.Max(0, r.Progress)) + " / " + r.Target;
        }
    }

    // ================================================================================================ hunt
    public sealed class HuntItem
    {
        public int Id, Count;
        public long Value;
        public string Name = "?";
        public int Rarity;
        public bool Unique, Orb;
    }

    public sealed class HuntKill { public string Name = "?"; public int Count; }

    public sealed class RestockQuote
    {
        public long Gold, Fee, Money;
        public int Pct;
        public string Why = "";
        public readonly List<KeyValuePair<int, string>> Rows = new List<KeyValuePair<int, string>>();
    }

    public sealed class HuntTracker
    {
        public const byte Opcode = 241;
        readonly ExtOpcodes ext;
        public Func<double> Clock = () => 0;
        public bool HasState, Paused;
        public double Seconds, ReceivedAt;
        public long Xp, Xph, Lv, Lvh, Sv, Svh, Pf, Pfh, Dmg, Heal, Kc;
        public double Dps, Hps;
        public long Left, Ttl = -1;
        public int Level;
        public readonly List<HuntKill> Kills = new List<HuntKill>();
        public readonly List<HuntItem> Loot = new List<HuntItem>(), Supplies = new List<HuntItem>(), Drops = new List<HuntItem>();
        public RestockQuote Quote;
        /// <summary>Set when the server's state says open: the window shows itself.</summary>
        public bool OpenRequested;
        public Action Changed = delegate { };

        public HuntTracker(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Open() { ext.Send(Opcode, "open", new Dictionary<string, object>()); }
        public void Close() { ext.Send(Opcode, "close", new Dictionary<string, object>()); }
        public void TogglePause() { if (HasState) ext.Send(Opcode, Paused ? "resume" : "pause", new Dictionary<string, object>()); }
        public void Reset() { ext.Send(Opcode, "reset", new Dictionary<string, object>()); }
        public void AskRestock() { ext.Send(Opcode, "restockQuote", new Dictionary<string, object>()); }
        public void Restock() { ext.Send(Opcode, "restock", new Dictionary<string, object>()); Quote = null; }

        /// <summary>The session seconds shown now: the server's value plus the time since it arrived while the session runs.</summary>
        public double Elapsed(double nowMs) => Paused ? Seconds : Seconds + Math.Max(0, (nowMs - ReceivedAt) / 1000.0);

        static long L(object d, string k) => (long)Json.Number(d, k);

        public void Handle(string action, object data)
        {
            if (action == "restockQuote" && data is Dictionary<string, object>)
            {
                var q = new RestockQuote { Gold = L(data, "gold"), Fee = L(data, "fee"), Pct = Json.Int(data, "pct"), Money = L(data, "money"), Why = Json.Text(data, "why") };
                foreach (object r in Json.List(data, "rows"))
                    if (r is List<object> a && a.Count >= 4) q.Rows.Add(new KeyValuePair<int, string>(a[1] is double c ? (int)c : 0, a[3] as string ?? "?"));
                Quote = q;
                Changed();
                return;
            }
            if (action != "state" || !(data is Dictionary<string, object>)) return;
            HasState = true;
            Paused = Json.Int(data, "p") == 1;
            Seconds = Json.Number(data, "t");
            ReceivedAt = Clock();
            Xp = L(data, "xp"); Xph = L(data, "xph"); Level = Json.Int(data, "lvl"); Left = L(data, "left");
            Ttl = Json.Get(data, "ttl") is double t ? (long)t : -1;
            Lv = L(data, "lv"); Lvh = L(data, "lvh"); Sv = L(data, "sv"); Svh = L(data, "svh"); Pf = L(data, "pf"); Pfh = L(data, "pfh");
            Dmg = L(data, "dmg"); Dps = Json.Number(data, "dps"); Heal = L(data, "heal"); Hps = Json.Number(data, "hps"); Kc = L(data, "kc");
            Kills.Clear();
            foreach (object r in Json.List(data, "k"))
                if (r is List<object> a && a.Count >= 2) Kills.Add(new HuntKill { Name = a[0] as string ?? "?", Count = a[1] is double n ? (int)n : 0 });
            Rows(Loot, Json.List(data, "l"), false);
            Rows(Supplies, Json.List(data, "s"), true);
            Drops.Clear();
            foreach (object r in Json.List(data, "x"))
                if (r is List<object> a && a.Count >= 3)
                    Drops.Add(new HuntItem { Id = Int(a, 0), Count = Int(a, 1), Name = a[2] as string ?? "?", Rarity = a.Count > 3 ? Int(a, 3) : 0, Unique = a.Count > 4 && Int(a, 4) == 1, Orb = a.Count > 5 && Int(a, 5) == 1 });
            if (Json.Truthy(data, "open") || Json.Number(data, "open") == 1) OpenRequested = true;   // hunt.lua sends open = 1, a number (phase 13 track G)
            Changed();
        }

        static int Int(List<object> a, int i) => i < a.Count && a[i] is double d ? (int)d : 0;

        static void Rows(List<HuntItem> list, List<object> rows, bool supply)
        {
            list.Clear();
            foreach (object r in rows)
                if (r is List<object> a && a.Count >= 4)
                    list.Add(new HuntItem
                    {
                        Id = Int(a, 0), Count = Int(a, 1), Value = (long)(a[2] is double v ? v : 0), Name = a[3] as string ?? "?",
                        Rarity = supply ? 0 : Int(a, 4), Unique = !supply && Int(a, 5) == 1, Orb = !supply && Int(a, 6) == 1,
                    });
        }

        /// <summary>The next level text: the time at the current rate, "-" without one.</summary>
        public string NextLevel() => Ttl < 0 ? "-" : Fmt.Duration(Ttl);

        // the seven rarities (lootfilter): name and colour
        public static string RarityName(int r)
        {
            switch (r)
            {
                case 1: return Lk.N("Common");
                case 2: return Lk.N("Uncommon");
                case 3: return Lk.N("Magic");
                case 4: return Lk.N("Rare");
                case 5: case 6: case 7: case 8: case 9: return Lk.N("Legendary");
                case 10: case 11: case 12: case 13: case 14: case 15: return Lk.N("Divine");
                default: return null;
            }
        }

        public static string RarityColor(int r)
        {
            switch (r)
            {
                case 1: return "#c8c8c8";
                case 2: return "#5ccf5c";
                case 3: return "#4a90ff";
                case 4: return "#a35cf0";
                case 5: case 6: case 7: case 8: case 9: return "#ffd040";
                case 10: case 11: case 12: case 13: case 14: case 15: return "#c8e8ff";
                default: return "#d6c9ae";
            }
        }

        /// <summary>"[Legendary] Magic Sword", "[Unique] Soulreaper", "Orb of Upheaval" and its colour.</summary>
        public static string ItemLabel(HuntItem it, out string color)
        {
            string name = it.Name.Length > 0 ? char.ToUpperInvariant(it.Name[0]) + it.Name.Substring(1) : "?";
            if (it.Unique) { color = "#e07b24"; return "[" + Loc.T("Unique") + "] " + name; }
            string r = RarityName(it.Rarity);
            if (r != null) { color = RarityColor(it.Rarity); return "[" + Loc.T(r) + "] " + name; }
            color = it.Orb ? "#4fd8d0" : "#d6c9ae";
            return name;
        }

        /// <summary>Plain text of the session for the clipboard.</summary>
        public string Summary(double nowMs)
        {
            var sb = new StringBuilder();
            sb.AppendLine(Loc.T("Hunt session: {0}", Fmt.Duration(Elapsed(nowMs))));
            sb.AppendLine("Experience: " + Fmt.Exact(Xp) + " (" + Fmt.Exact(Xph) + "/h)");
            sb.AppendLine(Loc.T("Loot: {0} gold ({1}/h)", Fmt.Exact(Lv), Fmt.Exact(Lvh)));
            sb.AppendLine("Supplies: " + Fmt.Exact(Sv) + " gold");
            sb.AppendLine(Loc.T("Profit: {0} gold ({1}/h)", Fmt.Exact(Pf), Fmt.Exact(Pfh)));
            sb.Append("Kills: " + Fmt.Exact(Kc));
            foreach (var k in Kills) sb.Append("\n  " + k.Count + "x " + k.Name);
            return sb.ToString();
        }
    }

    // ================================================================================================ rift
    public sealed class RiftMod { public string Name = "", Text = "", Side = ""; public int Tier; public bool Boon; }

    public sealed class RiftHud
    {
        public const byte Opcode = 228;
        readonly ExtOpcodes ext;
        public Func<double> Clock = () => 0;
        public bool Active;
        public int Tier = 1, Total, Killed, BossAt, Lives, LivesMax, Limit;
        public double Left, Swift, ReceivedAt;
        public string Theme = "", Boss = "", State = "", BossName = "", Omen = "", Title = "";
        public readonly List<RiftMod> Mods = new List<RiftMod>();
        public readonly List<string> Notes = new List<string>();
        public int BonusQuantity, BonusRarity, BonusExperience;
        public string ResultText = "", Result = "";
        public double ExitIn;
        /// <summary>When the HUD hides itself after an end message (ms on the session clock), -1 none.</summary>
        public double HideAt = -1;
        public Action Changed = delegate { };

        public RiftHud(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public void Query() { ext.Send(Opcode, "query", new Dictionary<string, object>()); }

        public void Handle(string action, object d)
        {
            if (action == "start" || action == "update")
            {
                if (!(d is Dictionary<string, object>)) d = new Dictionary<string, object>();
                if (action == "start" || !Active) { Result = ""; ResultText = ""; HideAt = -1; }
                Active = true;
                Tier = Json.Int(d, "tier", 1); Theme = Json.Text(d, "theme"); Left = Json.Number(d, "left"); Limit = Json.Int(d, "limit");
                Total = Json.Int(d, "total"); Killed = Json.Int(d, "killed"); BossAt = Json.Int(d, "bossAt"); Boss = Json.Text(d, "boss");
                State = Json.Text(d, "state"); BossName = Json.Text(d, "bossName"); Omen = Json.Text(d, "omen"); Title = Json.Text(d, "title");
                Lives = Json.Get(d, "lives") is double l ? (int)l : -1; LivesMax = Json.Int(d, "livesMax");
                Swift = Json.Number(d, "swift");
                Mods.Clear();
                foreach (object m in Json.List(d, "mods"))
                    Mods.Add(new RiftMod { Name = Json.Text(m, "name"), Text = Json.Text(m, "text"), Side = Json.Text(m, "side"), Tier = Json.Int(m, "tier"), Boon = Json.Truthy(m, "boon") });
                Notes.Clear();
                foreach (object n in Json.List(d, "notes")) if (n is string s) Notes.Add(s);
                object b = Json.Get(d, "bonus");
                BonusQuantity = Json.Int(b, "quantity"); BonusRarity = Json.Int(b, "rarity"); BonusExperience = Json.Int(b, "experience");
                ReceivedAt = Clock();
            }
            else if (action == "end")
            {
                if (!(d is Dictionary<string, object>)) return;
                string result = Json.Text(d, "result");
                if (Active)
                {
                    State = result == "success" || result == "left" ? result : "failed";
                    if (result == "success") Boss = "dead";
                }
                else { Active = true; State = result == "success" || result == "left" ? result : "failed"; }
                Result = result;
                ResultText = Json.Text(d, "text");
                ExitIn = Json.Number(d, "exitIn");
                HideAt = Clock() + (ExitIn > 0 ? (ExitIn + 2) * 1000 : 8000);
            }
            else return;
            Changed();
        }

        public void Hide() { Active = false; HideAt = -1; Result = ""; ResultText = ""; Changed(); }

        /// <summary>Seconds left now from the value the server sent.</summary>
        public double LeftNow(double nowMs) => Math.Max(0, Left - Math.Max(0, (nowMs - ReceivedAt) / 1000.0));

        public int BossPercent()
        {
            if (Boss == "alive" || Boss == "dead") return 100;
            if (BossAt <= 0) return 100;
            return Math.Min(100, Killed * 100 / BossAt);
        }

        public string BossLine()
        {
            if (Omen.Length > 0 && Boss == "waiting") return Loc.T("The guardian {0} is coming...", BossName);
            if (Boss == "alive") return Loc.T("The guardian {0} is here!", BossName);
            if (Boss == "dead") return Loc.T("The guardian is slain.");
            int need = Math.Max(0, BossAt - Killed);
            return need == 1 ? Loc.T("Guardian in {0} kill", need) : Loc.T("Guardian in {0} kills", need);
        }

        public string BonusLine()
        {
            var parts = new List<string>();
            if (BonusQuantity > 0) parts.Add("+" + BonusQuantity + "% " + Loc.T("quantity"));
            if (BonusRarity > 0) parts.Add("+" + BonusRarity + "% " + Loc.T("rarity"));
            if (BonusExperience > 0) parts.Add("+" + BonusExperience + "% " + Loc.T("experience"));
            return string.Join(", ", parts);
        }

        static readonly string[] Roman = { "I", "II", "III", "IV", "V" };

        public static string ModLine(RiftMod m)
        {
            string name = m.Name;
            if (name.Length > 0 && m.Tier >= 1 && m.Tier <= 5) name += " " + Roman[m.Tier - 1];
            if (name.Length > 0 && m.Text.Length > 0) return name + ": " + m.Text;
            return name.Length > 0 ? name : m.Text;
        }

        public string LivesLine() => Lives < 0 ? "" : LivesMax > 0 ? Loc.T("Lives: {0} / {1}", Lives, LivesMax) : Loc.T("Lives: {0}", Lives);

        public string SwiftLine(double leftNow, out bool met)
        {
            met = false;
            if (Swift <= 0 || Limit <= 0) return "";
            double elapsed = Math.Max(0, Limit - leftNow);
            if (elapsed <= Swift) { met = true; return Loc.T("Swift: seal within {0} ({1} to spare)", Fmt.Clock(Swift), Fmt.Clock(Swift - elapsed)); }
            return Loc.T("Swift: missed ({0})", Fmt.Clock(Swift));
        }

        /// <summary>The clock colour: gold, orange under a minute, red under 20 s.</summary>
        public static string ClockColor(double left) => left <= 20 ? "#ff4030" : left <= 60 ? "#ff9a30" : "#f4d27a";
    }

    // ================================================================================================ info and services
    public sealed class InfoButton
    {
        public string Text = "", Id = "", Param = "", Hint = "", Need = "", Why = "", Fn = "";
    }

    public sealed class InfoRow
    {
        public string Label = "", Hint = "", Edit = "", Combo = "";
        public InfoButton[] Buttons = new InfoButton[0];
    }

    public sealed class InfoPage
    {
        public string Id = "", Title = "", Text = "", Idle = "", State = "";
        public string[] Auto = new string[0], Ids = new string[0];
        public Dictionary<string, string> Headings = new Dictionary<string, string>();
        public bool Store;
        public InfoRow[] Rows = new InfoRow[0];
    }

    public sealed class StoreRow { public int Id, Item; public string Kind = "", Name = ""; public long Price, Missing; public bool Afford; }

    public sealed class ChaosInfo
    {
        public const byte Opcode = 237;
        readonly ExtOpcodes ext;
        public bool HasCatalog;
        public readonly HashSet<string> Offered = new HashSet<string>();
        public string Vocations = "";
        public Dictionary<string, object> Services;
        public string Output = "", LastResult = "";
        public string Current = "";
        public Dictionary<string, object> StoreData;
        /// <summary>A page the server asked to open (an NPC), for the window to show.</summary>
        public string OpenPage = "";
        public Action Changed = delegate { };

        public ChaosInfo(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        static InfoButton B(string text, string id = "", string param = "", string hint = "", string need = "", string why = "", string fn = "")
            => new InfoButton { Text = Lk.N(text), Id = id, Param = param, Hint = hint.Length > 0 ? Lk.N(hint) : "", Need = need, Why = why.Length > 0 ? Lk.N(why) : "", Fn = fn };

        static InfoRow R(string label, string edit, string combo, string hint, params InfoButton[] buttons)
            => new InfoRow { Label = label.Length > 0 ? Lk.N(label) : "", Edit = edit, Combo = combo, Hint = hint.Length > 0 ? Lk.N(hint) : "", Buttons = buttons };

        public const string Idle = "Press a button above. The answer shows here.";

        /// <summary>The pages of the main client's chaosinfoview.lua. Titles and texts are Loc keys.</summary>
        public static readonly InfoPage[] Pages =
        {
            new InfoPage
            {
                Id = "character", Title = Lk.N("Character Info"),
                Text = Lk.N("Your attacks, defenses and resistances, classes, ascension, double experience, position, the item sets you wear and your cards. The buttons show more."),
                Auto = new[] { "sheet", "classes", "ascension", "exp", "pos", "sets", "deck" },
                Headings = new Dictionary<string, string>
                {
                    { "classes", "Classes" }, { "ascension", "Ascension" }, { "exp", "Double EXP" }, { "pos", "Position" }, { "sets", "Item Sets" },
                    { "resis", "Resistances" }, { "kills", "Kills" }, { "deathlist", "Deaths" }, { "ancestral", "Ancestral Tasks" }, { "deck", "Card Deck" },
                },
                Rows = new[]
                {
                    R("", "", "", "",
                        B("Resistances", "resis", hint: "Your elemental resistances."), B("Kills", "kills", hint: "Your player kills."),
                        B("Deaths", "deathlist", hint: "Your last deaths."), B("Ancestral Tasks", "ancestral", hint: "Your task rank, points and current tasks."),
                        B("Card Deck", "deck", hint: "Your cards and what they give, the decks you carry and how to get one."),
                        B("Item Sets", "sets", hint: "The item sets you wear and their bonuses.")),
                },
            },
            new InfoPage
            {
                Id = "services", Title = Lk.N("Services"),
                Text = Lk.N("Store tokens (name and vocation change), the free class switch, familiars, the tutorial and web shop items."),
                State = "services",
                Rows = new[]
                {
                    R("New name", "name", "", "Type the new name. You are logged out to apply it.",
                        B("Change Name", "changename", "$", "Uses one Name Change token.", "nameTokens", "You have no Name Change token. Buy one in the store.")),
                    R("Class", "", "vocations", "The class to change to.",
                        B("Change Vocation", "changevocation", "$", "Uses one Vocation Change token.", "vocationTokens", "You have no Vocation Change token. Buy one in the store."),
                        B("Free Switch", "ascend", "$", "Your one free switch to the other class of your line.", "freeSwitch", "You have no free switch.")),
                    R("Familiar", "", "", "Familiars answer from level 200.",
                        B("Summon", "summonfamiliar", hint: "Summon your familiar.", need: "familiarReady", why: "Familiars need level 200."),
                        B("Level", "familiarlevel", hint: "Your familiar's level.", need: "familiarReady", why: "Familiars need level 200."),
                        B("Choose", "choosefamiliar", hint: "Choose your familiar.")),
                    R("Other", "", "", "The tutorial, boss rooms and the web shop.",
                        B("Leave Tutorial", "skiptutorial", hint: "Leave the tutorial island now.", need: "inTutorial", why: "You are not in the tutorial."),
                        B("Leave Boss Room", "leaveroom", hint: "Leave the boss room you are in, out to its exit. Not while you are in a fight.", need: "inBossRoom", why: "You are not in a boss room."),
                        B("Claim Web Shop Items", "webshop", hint: "Collect what you bought on the website.", need: "webshopOrders", why: "Nothing to claim.")),
                    R("Plate frame", "", "frames", "The frame around your name plate.",
                        B("Use Frame", "plateframe", "$", "Show the chosen frame.", "frames", "You own no frame. Store > Name Plates."),
                        B("My Frames", "plateframe", "list", "List the frames you own."),
                        B("Title Frame", "plateframe", "off", "Go back to your title's own frame.", "activeFrame", "Your title's own frame is shown already.")),
                },
            },
            new InfoPage
            {
                Id = "house", Title = Lk.N("House"), Text = Lk.N("Stand in front of a house door to buy it. Selling hands your house to another player."),
                Idle = Lk.N("Stand in front of a house door and press Buy This House. The answer shows here."),
                Rows = new[]
                {
                    R("", "", "", "", B("Buy This House", "buyhouse", hint: "Buy the house whose door you face."), B("Leave My House", "leavehouse", hint: "Give up your house.")),
                    R("Buyer", "buyer", "", "The character that gets your house.", B("Sell House", "sellhouse", "$", "Hand your house to this character.")),
                },
            },
            new InfoPage
            {
                Id = "rift", Title = Lk.N("Rift Keys"),
                Text = Lk.N("The rift you are in and every Rift Key you carry, with its modifiers. Use a key to open its rift."),
                Auto = new[] { "rift" },
            },
            new InfoPage
            {
                Id = "events", Title = Lk.N("Events"), Text = Lk.N("Server events running today, world buffs and the world boss."),
                Auto = new[] { "events", "worldbuffs", "worldboss" },
                Headings = new Dictionary<string, string> { { "events", "Events today" }, { "worldbuffs", "World buffs" }, { "worldboss", "World boss" } },
            },
            new InfoPage
            {
                Id = "ancestral", Title = Lk.N("Ancestral Store"), Text = Lk.N("Spend your Ancestral Points (from the task NPCs)."), Store = true, Ids = new[] { "ancestralstore" },
            },
            new InfoPage
            {
                Id = "server", Title = Lk.N("Server Info"), Text = Lk.N("Rates, uptime and who is online."), Auto = new[] { "serverinfo", "uptime", "online" },
            },
        };

        public static InfoPage Page(string id)
        {
            foreach (var p in Pages) if (p.Id == id) return p;
            return null;
        }

        // ------------------------------------------------------------------------------------ requests
        void Send(string action, Dictionary<string, object> payload = null)
        {
            var root = new Dictionary<string, object> { { "action", action } };
            if (payload != null) foreach (var kv in payload) root[kv.Key] = kv.Value;
            ext.SendText(Opcode, Json.Serialize(root));
        }

        public void RequestCatalog() { Send("catalog"); }
        public void RequestServices() { Send("services"); }
        public void RequestStore() { Send("store"); }
        public void Buy(int id, int count = 1) { Send("buy", new Dictionary<string, object> { { "id", id }, { "count", count } }); }

        public void Run(string page, List<string> ids, List<string> param)
        {
            if (ids.Count == 0) return;
            Send("run", new Dictionary<string, object>
            {
                { "page", page }, { "ids", new List<object>(ids) }, { "params", new List<object>(param) },
            });
        }

        // ------------------------------------------------------------------------------------ rules (chaosinfoview.lua)
        public List<string> AutoIds(InfoPage p)
        {
            var list = new List<string>();
            foreach (string id in p.Auto) if (Offered.Contains(id)) list.Add(id);
            return list;
        }

        public bool ButtonShown(InfoButton b) => b.Fn.Length > 0 || (b.Id.Length > 0 && Offered.Contains(b.Id));

        public bool PageShown(InfoPage p)
        {
            if (!HasCatalog) return true;
            foreach (string id in p.Auto) if (Offered.Contains(id)) return true;
            foreach (string id in p.Ids) if (Offered.Contains(id)) return true;
            foreach (var r in p.Rows) foreach (var b in r.Buttons) if (b.Id.Length > 0 && Offered.Contains(b.Id)) return true;
            return false;
        }

        public bool IsPageOffered(string id) { var p = Page(id); return p != null && PageShown(p); }

        /// <summary>The param sent for a button: its template with $ replaced by the field text, null when the field is needed but empty.</summary>
        public static string Param(string template, string field)
        {
            if (template.Length == 0) return "";
            if (template.IndexOf('$') < 0) return template;
            string v = (field ?? "").Trim();
            return v.Length == 0 ? null : template.Replace("$", v);
        }

        /// <summary>Is the state field a button needs met? No state yet, or no need: yes.</summary>
        public bool NeedMet(string need)
        {
            if (need.Length == 0 || Services == null) return true;
            object v = Json.Get(Services, need);
            if (v == null) return true;
            if (v is double d) return d > 0 || d == -1;
            if (v is string s) return s.Length > 0;
            if (v is List<object> l) return l.Count > 0;
            return Json.Truthy(v);
        }

        /// <summary>The choice list "warrior|juggernaut" -> {"Warrior", "Juggernaut"} as (text, value).</summary>
        public List<KeyValuePair<string, string>> VocationOptions()
        {
            var o = new List<KeyValuePair<string, string>>();
            foreach (string w in Vocations.Split(new[] { '|' }, StringSplitOptions.RemoveEmptyEntries))
                o.Add(new KeyValuePair<string, string>(char.ToUpperInvariant(w[0]) + w.Substring(1), w.ToLowerInvariant()));
            return o;
        }

        public List<KeyValuePair<string, string>> FrameOptions()
        {
            var o = new List<KeyValuePair<string, string>>();
            if (Services != null)
                foreach (object f in Json.List(Services, "frames"))
                    if (f is string s && s.Length > 0) o.Add(new KeyValuePair<string, string>(char.ToUpperInvariant(s[0]) + s.Substring(1), s));
            return o;
        }

        public List<StoreRow> StoreRows(out long points)
        {
            var rows = new List<StoreRow>();
            points = StoreData == null ? 0 : (long)Json.Number(StoreData, "points");
            if (StoreData == null) return rows;
            foreach (object e in Json.List(StoreData, "entries"))
            {
                if (!(Json.Get(e, "price") is double price) || !(Json.Get(e, "id") is double id) || !(Json.Get(e, "name") is string name)) continue;
                rows.Add(new StoreRow { Id = (int)id, Kind = Json.Text(e, "kind", "Other"), Name = name, Item = Json.Int(e, "item"), Price = (long)price, Afford = points >= price, Missing = Math.Max(0, (long)price - points) });
            }
            rows.Sort((a, b) => a.Kind != b.Kind ? string.CompareOrdinal(a.Kind, b.Kind) : a.Price != b.Price ? a.Price.CompareTo(b.Price) : a.Id.CompareTo(b.Id));
            return rows;
        }

        /// <summary>The result parts -> the page text, a heading over each part that has one.</summary>
        public static string ResultText(List<object> parts, Dictionary<string, string> headings)
        {
            var o = new List<string>();
            foreach (object p in parts)
            {
                string text = Json.Text(p, "text");
                if (text.Length == 0) continue;
                string id = Json.Text(p, "id");
                if (headings != null && headings.TryGetValue(id, out string h)) o.Add("[ " + Loc.T(h) + " ]\n" + text);
                else o.Add(text);
            }
            return string.Join("\n\n", o);
        }

        /// <summary>The Services status block.</summary>
        public string ServicesText()
        {
            var s = Services;
            if (s == null) return Loc.T("Loading...");
            var lines = new List<string>
            {
                Loc.T("Name Change tokens: {0}", Json.Int(s, "nameTokens")),
                Loc.T("Vocation Change tokens: {0}", Json.Int(s, "vocationTokens")),
            };
            string fs = Json.Text(s, "freeSwitch");
            lines.Add(fs.Length > 0 ? Loc.T("Free switch: available (to {0})", fs) : Loc.T("Free switch: none"));
            lines.Add(Json.Truthy(s, "familiarReady") ? Loc.T("Familiar: available") : Loc.T("Familiar: from level {0}", Json.Int(s, "familiarLevel", 200)));
            if (Json.Truthy(s, "inTutorial")) lines.Add(Loc.T("Tutorial: you are on the tutorial island"));
            if (Json.Get(s, "webshopOrders") is double w && w >= 0) lines.Add(Loc.T("Web shop items to claim: {0}", (int)w));
            var frames = FrameOptions();
            if (frames.Count > 0) lines.Add(Loc.T("Your frames: {0}", string.Join(", ", frames.ConvertAll(f => f.Key))));
            else lines.Add(Loc.T("Your frames: none (Store > Name Plates)"));
            string active = Json.Text(s, "activeFrame");
            if (active.Length > 0) lines.Add(Loc.T("Frame shown: {0}", char.ToUpperInvariant(active[0]) + active.Substring(1)));
            string text = "[ " + Loc.T("Status") + " ]\n" + string.Join("\n", lines);
            if (LastResult.Length > 0) text = "[ " + Loc.T("Last action") + " ]\n" + LastResult + "\n\n" + text;
            return text;
        }

        public void Handle(string action, object d)
        {
            switch (action)
            {
                case "catalog":
                    HasCatalog = true;
                    Offered.Clear();
                    foreach (object id in Json.List(d, "ids")) if (id is string s) Offered.Add(s);
                    Vocations = Json.Text(d, "vocations");
                    break;
                case "result":
                {
                    string pg = Json.Text(d, "page");
                    if (pg != Current && pg.Length != 0) return;
                    var page = Page(Current);
                    string text = ResultText(Json.List(d, "parts"), page?.Headings);
                    if (page != null && page.State == "services") { LastResult = text; RequestServices(); }
                    else Output = text.Length > 0 ? text : Loc.T("Nothing to show.");
                    break;
                }
                case "services": Services = d as Dictionary<string, object> ?? new Dictionary<string, object>(); break;
                case "store": StoreData = d as Dictionary<string, object> ?? new Dictionary<string, object>(); break;
                case "npc":
                    string np = Json.Text(d, "page");
                    if (Page(np) != null) OpenPage = np;
                    break;
                default: return;
            }
            Changed();
        }

        /// <summary>Opens a page: asks what the page needs and sets the first output text.</summary>
        public void Show(string id)
        {
            var page = Page(id);
            if (page == null) return;
            if (!HasCatalog) RequestCatalog();
            Current = id;
            Output = "";
            if (page.Store) { RequestStore(); }
            else if (page.State == "services") { LastResult = ""; RequestServices(); }
            else
            {
                var auto = AutoIds(page);
                if (auto.Count > 0) { Output = Loc.T("Loading..."); Run(id, auto, auto.ConvertAll(_ => "")); }
                else Output = Loc.T(page.Idle.Length > 0 ? page.Idle : Idle);
            }
            Changed();
        }

        /// <summary>A button pressed: its command, then the page's auto commands again so the page shows the new state.</summary>
        public void Press(InfoPage page, InfoRow row, InfoButton b, string fieldText)
        {
            string param = Param(b.Param, fieldText);
            if (param == null) { Output = Loc.T("Fill in \"{0}\" first.", Loc.T(row.Label)); Changed(); return; }
            var ids = new List<string> { b.Id };
            var ps = new List<string> { param };
            foreach (string id in AutoIds(page)) { ids.Add(id); ps.Add(""); }
            Run(page.Id, ids, ps);
        }
    }

    // ================================================================================================ the hub
    /// <summary>One of each system above, built by the session.</summary>
    public sealed class Progression
    {
        public readonly PassiveTree Tree;
        public readonly SkillStats Stats;
        public readonly Goals Goals;
        public readonly HuntTracker Hunt;
        public readonly RiftHud Rift;
        public readonly ChaosInfo Info;
        public readonly MenuUnlocks Unlocks;
        bool started;

        public Progression(ExtOpcodes ext, Func<double> clock)
        {
            Tree = new PassiveTree(ext);
            Stats = new SkillStats(ext);
            Goals = new Goals(ext);
            Hunt = new HuntTracker(ext) { Clock = clock };
            Rift = new RiftHud(ext) { Clock = clock };
            Info = new ChaosInfo(ext);
            Unlocks = new MenuUnlocks(ext) { Clock = clock };
        }

        /// <summary>The first requests after the login (the main client sends them in onGameStart).</summary>
        public void Start()
        {
            if (started) return;
            started = true;
            Unlocks.Hello();
            Stats.Get();
            Rift.Query();
            Goals.RequestTracker();
        }
    }
}
