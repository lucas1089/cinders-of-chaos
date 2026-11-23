// The live state of the journey bot for the staff's bot map (O727, server/README.md "Bot live map (O727)"). Pure C#, no Unity types, no network. The same file format as the
// Python bots (server/tools/bot_live.py): ONE JSON line in <live dir>/<slug>.json with the name, class, level, position, goal and since when, the reason (why), the spot, what it does
// now, the plan (numbered next steps) and the last 50 log lines with their time; "src": "cs". The website reads the folder (plugins/chaos/botmap_lib.php) and shows the bots to the staff
// only. Nothing here decides anything: the texts are the facts of the decisions JourneyHunts.Pick and JourneyRules.TownTrip already made. No account, no password, no address is ever in
// the file. Core.Tests/BotLiveTests.cs proves the format, the limits, the rate of the writer and the texts; the runtime is Core.LiveCheck/LiveJourney.cs.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core
{
    public sealed class BotLiveState
    {
        public const int Version = 1, LogMax = 50, PlanMax = 8, TextMax = 160, FieldMax = 240;
        static readonly Regex TesterName = new Regex(@"^Tester [A-Z][a-z][a-z]$", RegexOptions.CultureInvariant);

        public readonly string Name;
        public string Class = "", Goal = "", Why = "", Spot = "", Now = "";
        public int Level;
        public int[] Pos;
        public long GoalSince;
        public readonly List<string> Plan = new List<string>();
        readonly List<KeyValuePair<long, string>> log = new List<KeyValuePair<long, string>>();
        public bool Dirty = true;

        public BotLiveState(string name, long nowSec)
        {
            Name = name ?? "";
            GoalSince = nowSec;
        }

        /// <summary>A tester name: "Tester" and three letters (server/tools/tester_core.py NAME_RE). Nothing else is ever published.</summary>
        public static bool IsTester(string name) => name != null && TesterName.IsMatch(name);

        /// <summary>The file name part of a tester name ("tester-abc"), "" for any other name.</summary>
        public static string Slug(string name) => IsTester(name) ? name.ToLowerInvariant().Replace(' ', '-') : "";

        /// <summary>One line of printable text, cut to the limit.</summary>
        public static string Clean(string text, int limit)
        {
            if (text == null) return "";
            var sb = new StringBuilder(Math.Min(text.Length, limit));
            bool space = true;
            foreach (char c in text)
            {
                if (char.IsControl(c) || char.IsWhiteSpace(c)) { if (!space) { sb.Append(' '); space = true; } continue; }
                sb.Append(c); space = false;
                if (sb.Length >= limit) break;
            }
            return sb.ToString().TrimEnd();
        }

        public void SetClass(string c) { c = Clean(c, 40); if (c != Class) { Class = c; Dirty = true; } }
        public void SetLevel(int level) { if (level >= 0 && level != Level) { Level = level; Dirty = true; } }
        public void SetPos(int x, int y, int z)
        {
            if (x < 0 || x > 65535 || y < 0 || y > 65535 || z < 0 || z > 15) return;
            if (Pos != null && Pos[0] == x && Pos[1] == y && Pos[2] == z) return;
            Pos = new[] { x, y, z };
            Dirty = true;
        }

        /// <summary>A new goal restarts "since"; the same goal keeps it. Why, spot and plan follow the goal.</summary>
        public void SetGoal(string goal, string why, string spot, IEnumerable<string> plan, long nowSec)
        {
            goal = Clean(goal, 60); why = Clean(why, FieldMax); spot = Clean(spot, FieldMax);
            var p = (plan ?? new string[0]).Select(x => Clean(x, FieldMax)).Where(x => x.Length > 0).Take(PlanMax).ToList();
            if (goal != Goal) { Goal = goal; GoalSince = nowSec; Dirty = true; }
            if (why != Why) { Why = why; Dirty = true; }
            if (spot != Spot) { Spot = spot; Dirty = true; }
            if (!p.SequenceEqual(Plan)) { Plan.Clear(); Plan.AddRange(p); Dirty = true; }
        }

        /// <summary>One line at the end of the log (newest last); it is also what the bot does now.</summary>
        public void Log(string text, long nowSec)
        {
            string line = Clean(text, TextMax);
            if (line.Length == 0) return;
            log.Add(new KeyValuePair<long, string>(nowSec, line));
            if (log.Count > LogMax) log.RemoveRange(0, log.Count - LogMax);
            Now = line;
            Dirty = true;
        }

        public IReadOnlyList<KeyValuePair<long, string>> Lines => log;

        /// <summary>The one JSON line (with its newline), as of `nowSec`.</summary>
        public string ToLine(long nowSec)
        {
            var d = new Dictionary<string, object>
            {
                { "v", Version }, { "name", Name }, { "class", Class }, { "level", Level },
                { "pos", Pos == null ? null : (object)Pos.Cast<object>().ToList() },
                { "goal", Goal }, { "goal_since", GoalSince }, { "why", Why }, { "spot", Spot }, { "now", Now },
                { "plan", Plan.Cast<object>().ToList() },
                { "log", log.Select(kv => (object)new List<object> { kv.Key, kv.Value }).ToList() },
                { "t", nowSec }, { "src", "cs" },
            };
            return Escape(Json.Serialize(d)) + "\n";
        }

        /// <summary>Everything outside ASCII leaves as \uXXXX (the website reads UTF-8 either way; this keeps the file plain).</summary>
        static string Escape(string json)
        {
            var sb = new StringBuilder(json.Length);
            foreach (char c in json)
                if (c < 0x80) sb.Append(c); else sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
            return sb.ToString();
        }
    }

    /// <summary>The writer: one file, atomic (a temp file, then a rename), at most one write every WriteEverySec when something changed and at least one every HeartbeatSec
    /// (so the page sees the bot is there). A folder that cannot be written is not an error of the bot.</summary>
    public sealed class BotLiveWriter
    {
        public const double WriteEverySec = 3, HeartbeatSec = 15;
        readonly string folder;
        readonly Func<long> clock;
        long lastWrite = long.MinValue;
        public int Writes;

        public BotLiveWriter(string folder, Func<long> clockSec)
        {
            this.folder = folder;
            clock = clockSec;
        }

        public string PathOf(BotLiveState s) => Path.Combine(folder, BotLiveState.Slug(s.Name) + ".json");

        /// <summary>Writes the state when it is due; true when a file was written.</summary>
        public bool Flush(BotLiveState s, bool force = false)
        {
            if (s == null || BotLiveState.Slug(s.Name).Length == 0) return false;
            long now = clock();
            bool first = lastWrite == long.MinValue;
            bool due = force || first || (s.Dirty && now - lastWrite >= WriteEverySec) || now - lastWrite >= HeartbeatSec;
            if (!due) return false;
            try
            {
                Directory.CreateDirectory(folder);
                string path = PathOf(s), tmp = path + ".tmp";
                File.WriteAllText(tmp, s.ToLine(now), new UTF8Encoding(false));
                // a rename, so the page never reads half a file (File.Replace and File.Move exist in every .NET the Core is built for)
                if (File.Exists(path)) File.Replace(tmp, path, null); else File.Move(tmp, path);
            }
            catch (Exception e) when (e is IOException || e is UnauthorizedAccessException) { return false; }
            lastWrite = now;
            s.Dirty = false;
            Writes++;
            return true;
        }

        /// <summary>The bot is gone: its file goes with it (a file left behind turns grey on the page after 2 minutes and is dropped after 10).</summary>
        public void Remove(BotLiveState s)
        {
            try { File.Delete(PathOf(s)); } catch (Exception) { }
        }
    }

    /// <summary>The words of the bot's reasons: facts of the hunt it picked and the trip it called, never a new decision.</summary>
    public static class BotLiveText
    {
        public static string Spaced(long n) => n.ToString("N0", CultureInfo.InvariantCulture).Replace(',', ' ');

        /// <summary>Why this hunt: the band holds the level (or does not: the closest one), how far it is, and what the bot has measured so far.</summary>
        public static string WhyHunt(JourneyHunt h, int level, Pos from, double xpPerHour)
        {
            if (h == null) return "";
            int d = Math.Max(Math.Abs(h.At.X - from.X), Math.Abs(h.At.Y - from.Y));
            string fit = level >= h.Lo && level <= h.Hi ? "level " + level + " is inside levels " + h.Lo + "-" + h.Hi
                       : level > h.Hi ? "level " + level + " is above levels " + h.Lo + "-" + h.Hi + ": the closest band below it"
                       : "level " + level + " is below levels " + h.Lo + "-" + h.Hi + ": the closest band above it";
            string t = fit + " of " + h.Name + ", " + d + " tiles away" + (h.At.Z != from.Z ? " and " + Math.Abs(h.At.Z - from.Z) + " floor(s) off" : "");
            if (xpPerHour > 0) t += "; it has measured about " + Spaced((long)xpPerHour) + " exp/h so far";
            return t;
        }

        public static string WhyTrip(string reason)
        {
            switch (reason)
            {
                case "cap": return "town trip: its capacity is nearly full";
                case "backpack": return "town trip: the backpack has two free slots or fewer";
                case "potions": return "town trip: under " + JourneyRules.PotionsLow + " potions and the gold to buy more";
                default: return "town trip" + (string.IsNullOrEmpty(reason) ? "" : ": " + reason);
            }
        }

        /// <summary>The next steps while it hunts.</summary>
        public static List<string> HuntPlan(JourneyHunt h)
        {
            string name = h == null ? "here" : h.Name;
            return new List<string>
            {
                "Keep hunting " + name + " while level " + (h == null ? "" : h.Lo + "-" + h.Hi + " ") + "holds",
                "Fight with the class rotation; drink a potion under " + (int)JourneyRules.HealPotionPct + "% health",
                "Town trip when the capacity or the backpack is full or the potions run out (sell, buy potions)",
                "Pick the next hunt when the level outgrows this one",
            };
        }
    }
}
