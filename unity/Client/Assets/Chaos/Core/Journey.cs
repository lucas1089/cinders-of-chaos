// Journey bot decision logic (O542, unity/README.md "Journey bots (O542)"). Pure C#, no Unity types, no network: what the bot decides from numbers it was given.
// The runtime that plays on a real server is unity/Core.LiveCheck/LiveJourney.cs; this file is what Core.Tests (JourneyTests.cs) proves without a server:
//   hunt pick by level and distance from the map marks, the thresholds (heal, potion, town trip), the progress watchdog (stuck steps), the activity chooser (hunt, town,
//   explore, talk, system, idle with imperfect timing), the memory of seen tiles with a path finder that explores toward a goal and takes floor changes, the metrics maths
//   (kills / xp / gold per hour, minutes per level) and the coverage table (systems, opcodes, areas: touched / not touched / failed).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core
{
    /// <summary>A small seeded random source (xorshift), so a run and its test repeat.</summary>
    public sealed class JourneyRng
    {
        ulong x;
        public JourneyRng(ulong seed) { x = seed == 0 ? 0x9E3779B97F4A7C15UL : seed; }
        public ulong NextU()
        {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17;
            return x;
        }
        /// <summary>0 .. n-1.</summary>
        public int Next(int n) => n <= 1 ? 0 : (int)(NextU() % (ulong)n);
        /// <summary>0 .. 1.</summary>
        public double Unit() => (NextU() >> 11) / (double)(1UL << 53);
        public int Range(int lo, int hi) => hi <= lo ? lo : lo + Next(hi - lo + 1);
    }

    /// <summary>A hunting area of the map marks: "Hunting: Rat, Cave Rat (level 1-10)" at a position.</summary>
    public sealed class JourneyHunt
    {
        public string Name = "";
        public readonly List<string> Monsters = new List<string>();
        public int Lo, Hi;
        public Pos At;
        public string Key => Name + "@" + At.X + "," + At.Y + "," + At.Z;
        public int Mid => (Lo + Hi) / 2;
    }

    public static class JourneyHunts
    {
        static readonly Regex Name = new Regex(@"^Hunting:\s*(?<m>.+?)\s*\(level\s*(?<lo>\d+)\s*-\s*(?<hi>\d+)\)\s*$", RegexOptions.CultureInvariant);
        static readonly Regex Row = new Regex(@"\{\s*k\s*=\s*""(?<k>[a-z]+)""\s*,\s*x\s*=\s*(?<x>\d+)\s*,\s*y\s*=\s*(?<y>\d+)\s*,\s*z\s*=\s*(?<z>\d+)\s*,\s*n\s*=\s*""(?<n>[^""]*)""", RegexOptions.CultureInvariant);

        /// <summary>The marks of data/chaos_poi.lua (the generated table of the installed server: kind, position, name).</summary>
        public static List<MapMark> ParsePoiLua(string text)
        {
            var o = new List<MapMark>();
            foreach (Match m in Row.Matches(text ?? ""))
                o.Add(new MapMark { Kind = m.Groups["k"].Value, X = int.Parse(m.Groups["x"].Value, CultureInfo.InvariantCulture), Y = int.Parse(m.Groups["y"].Value, CultureInfo.InvariantCulture), Z = int.Parse(m.Groups["z"].Value, CultureInfo.InvariantCulture), Name = m.Groups["n"].Value });
            return o;
        }

        public static JourneyHunt ParseHunt(MapMark m)
        {
            if (m == null || m.Kind != "hunt") return null;
            var r = Name.Match(m.Name ?? "");
            if (!r.Success) return null;
            var h = new JourneyHunt { Name = r.Groups["m"].Value, Lo = int.Parse(r.Groups["lo"].Value, CultureInfo.InvariantCulture), Hi = int.Parse(r.Groups["hi"].Value, CultureInfo.InvariantCulture), At = new Pos(m.X, m.Y, m.Z) };
            foreach (string part in h.Name.Split(','))
            {
                string t = part.Trim();
                if (t.Length > 0) h.Monsters.Add(t);
            }
            return h;
        }

        public static List<JourneyHunt> FromMarks(IEnumerable<MapMark> marks) => marks.Select(ParseHunt).Where(h => h != null).ToList();

        /// <summary>The hunt a character of `level` goes to from `from`: the band holds the level, nearest first (a floor away costs 30 tiles, a level off the middle of the band 6), a little
        /// noise so three bots of one class do not all pick the same place. A hunt in `avoid` (given up, stuck, deadly) and one farther than `maxTravel` tiles are not picked. When
        /// nothing holds the level, the hunt whose band is closest below it (a stronger character farms an old place) comes, else the closest above.</summary>
        public static JourneyHunt Pick(IList<JourneyHunt> hunts, int level, Pos from, ISet<string> avoid, JourneyRng rng, int maxTravel = 400)
        {
            JourneyHunt best = null;
            double bestScore = double.MaxValue;
            foreach (var h in hunts)
            {
                if (avoid != null && avoid.Contains(h.Key)) continue;
                int d = Math.Max(Math.Abs(h.At.X - from.X), Math.Abs(h.At.Y - from.Y));
                if (d > maxTravel) continue;
                double gap = level < h.Lo ? (h.Lo - level) * 40.0 : level > h.Hi ? (level - h.Hi) * 12.0 : 0;
                double score = d + 30.0 * Math.Abs(h.At.Z - from.Z) + 6.0 * Math.Abs(level - h.Mid) / Math.Max(1.0, (h.Hi - h.Lo) / 10.0) + gap * 10.0;
                if (rng != null) score *= 1.0 + 0.15 * rng.Unit();
                if (score < bestScore) { bestScore = score; best = h; }
            }
            return best;
        }

        /// <summary>True when the monster name (the server adds a level tag "Rat [4]") is one the hunt lists. An empty list means any monster.</summary>
        public static bool Wants(JourneyHunt h, string monsterName)
        {
            if (h == null || h.Monsters.Count == 0) return true;
            string b = BaseName(monsterName);
            return h.Monsters.Any(m => string.Equals(m, b, StringComparison.OrdinalIgnoreCase));
        }

        public static string BaseName(string n)
        {
            n = n ?? "";
            int b = n.LastIndexOf(" [", StringComparison.Ordinal);
            return b > 0 && n.EndsWith("]", StringComparison.Ordinal) ? n.Substring(0, b) : n;
        }
    }

    /// <summary>What the bot reads of itself when it decides (all numbers, filled by the runtime from the parser).</summary>
    public sealed class JourneyVitals
    {
        public int Health, MaxHealth, Mana, MaxMana, Level;
        public uint FreeCap, TotalCap;
        public int BackpackFree = 99;
        public int HealthPotions, ManaPotions;
        public ulong Gold;
        public bool CanCast;
        public double HealthPct => MaxHealth <= 0 ? 100 : 100.0 * Health / MaxHealth;
        public double ManaPct => MaxMana <= 0 ? 100 : 100.0 * Mana / MaxMana;
    }

    public static class JourneyRules
    {
        /// <summary>The heal spell under this health percent (the Helper's heal rows are set by Auto setup; this is the bot's own back-up), the potion under the second.</summary>
        public const double HealSpellPct = 60, HealPotionPct = 40, ManaPotionPct = 25;
        /// <summary>Potions the bot wants to carry, and below which it goes to town (when it has the gold to buy).</summary>
        public const int PotionsWanted = 20, PotionsLow = 3;
        public const double TripCooldownMs = 8 * 60 * 1000;
        public const double CapFreeFraction = 0.12;

        public static bool DrinkHealth(JourneyVitals v) => v.HealthPotions > 0 && v.HealthPct < HealPotionPct;
        public static bool DrinkMana(JourneyVitals v) => v.ManaPotions > 0 && v.MaxMana > 0 && v.CanCast && v.ManaPct < ManaPotionPct;

        /// <summary>Why a trip to town is due, or "" (cap: free capacity under 12 percent and at most 15 oz; backpack: two free slots or less; potions: under 3 and the gold for 20 or more).
        /// Cap and backpack always count; potions wait for the cooldown since the last trip.</summary>
        public static string TownTrip(JourneyVitals v, double sinceLastTripMs, uint potionPrice)
        {
            if (v.TotalCap > 0 && v.FreeCap < Math.Max(15u, (uint)(v.TotalCap * CapFreeFraction))) return "cap";
            if (v.BackpackFree <= 2) return "backpack";
            int have = v.HealthPotions + (v.CanCast ? v.ManaPotions : 0);
            if (have < PotionsLow && potionPrice > 0 && v.Gold >= (ulong)potionPrice * 10 && sinceLastTripMs >= TripCooldownMs) return "potions";
            return "";
        }

        /// <summary>How many potions to buy with the gold the bot has: up to PotionsWanted, never more than half the gold.</summary>
        public static int BuyCount(ulong gold, int have, uint price)
        {
            if (price == 0) return 0;
            int want = Math.Max(0, PotionsWanted - have);
            ulong afford = gold / 2 / price;
            return (int)Math.Min((ulong)want, afford);
        }
    }

    /// <summary>The watchdog of a walk or a fight: no progress for a while is a stuck event. Level 1 after ReplanMs (the runtime plans again), level 2 after GiveUpMs (it gives up the
    /// spot: blocklist for a while, log the position), level 3 after the same spot gave up twice in a row (the bot walks away at random).</summary>
    public sealed class StuckWatch
    {
        public const double ReplanMs = 7000, GiveUpMs = 24000;
        Pos last;
        double lastChange = -1;
        long lastExp = -1;
        int level;
        public int GiveUps { get; private set; }

        public void Reset(double now) { lastChange = now; level = 0; }
        public void Hold(double now) { lastChange = now; level = 0; }

        /// <summary>Call with the clock, the position, the experience and whether the bot wants to move or fight. Returns 0 (fine), 1 (replan), 2 (give up the spot).</summary>
        public int Observe(double now, Pos pos, long exp, bool busy)
        {
            if (lastChange < 0 || !busy || pos.X != last.X || pos.Y != last.Y || pos.Z != last.Z || exp != lastExp)
            {
                last = pos; lastExp = exp; lastChange = now; level = 0;
                if (!busy) GiveUps = 0;
                return 0;
            }
            double idle = now - lastChange;
            if (idle >= GiveUpMs) { level = 0; GiveUps++; lastChange = now; return 2; }
            if (idle >= ReplanMs && level < 1) { level = 1; return 1; }
            return 0;
        }
    }

    public enum JourneyActivity { Hunt, Town, Explore, Talk, System, Idle }

    /// <summary>The human part: the bot does not only hunt. Weighted choice by level and need, with idle pauses of uneven length.</summary>
    public static class JourneyActivities
    {
        public sealed class Context
        {
            public int Level;
            public string TripReason = "";
            public double MinutesSinceExplore, MinutesSinceSystem, MinutesSinceTalk;
            public int UntouchedSystems, UnvisitedTowns, UntalkedNpcs;
            public bool Dead;
        }

        public const double ExploreEveryMin = 12, SystemEveryMin = 4, TalkEveryMin = 9;

        public static JourneyActivity Choose(Context c, JourneyRng rng)
        {
            if (c.TripReason.Length > 0) return JourneyActivity.Town;
            double hunt = 60, explore = 0, talk = 0, system = 0, idle = 6;
            if (c.UnvisitedTowns > 0 && c.Level >= 3) explore = 4 + Math.Min(20, c.MinutesSinceExplore / ExploreEveryMin * 10);
            if (c.UntouchedSystems > 0) system = 5 + Math.Min(24, c.MinutesSinceSystem / SystemEveryMin * 6);
            if (c.UntalkedNpcs > 0) talk = 3 + Math.Min(12, c.MinutesSinceTalk / TalkEveryMin * 6);
            double total = hunt + explore + talk + system + idle;
            double r = rng.Unit() * total;
            if ((r -= hunt) < 0) return JourneyActivity.Hunt;
            if ((r -= explore) < 0) return JourneyActivity.Explore;
            if ((r -= system) < 0) return JourneyActivity.System;
            if ((r -= talk) < 0) return JourneyActivity.Talk;
            return JourneyActivity.Idle;
        }

        /// <summary>How long a hunt lasts before the bot reconsiders (milliseconds): 3 to 9 minutes, uneven.</summary>
        public static double HuntSliceMs(JourneyRng rng) => rng.Range(180, 540) * 1000.0;

        /// <summary>An idle pause (standing, looking, a short chat pause): 2 to 25 seconds, most of them short.</summary>
        public static double IdleMs(JourneyRng rng)
        {
            double u = rng.Unit();
            return 2000 + 23000 * u * u;
        }

        /// <summary>The delay before the next action, a human's imperfect timing: 120 to 520 ms, now and then a long one (up to 1.8 s).</summary>
        public static double ReactionMs(JourneyRng rng)
        {
            double d = 120 + rng.Next(400);
            if (rng.Next(25) == 0) d += 300 + rng.Next(1400);
            return d;
        }
    }

    /// <summary>The tiles the bot has seen (the client forgets what is out of view; a player keeps a minimap): walkable, blocked, floor changes. A path finder over them that explores
    /// toward a goal it cannot see yet.</summary>
    public sealed class JourneyMap
    {
        public enum Cell : byte { Unknown = 0, Walk = 1, Blocked = 2, Change = 3 }

        public readonly Dictionary<Pos, Cell> Cells = new Dictionary<Pos, Cell>();
        /// <summary>Direction of each floor change tile: +1 goes down (z grows), -1 goes up.</summary>
        public readonly Dictionary<Pos, int> Changes = new Dictionary<Pos, int>();
        /// <summary>Tiles a walk failed on (a refused step, a door that stayed shut): avoided for a while.</summary>
        public readonly Dictionary<Pos, double> Bad = new Dictionary<Pos, double>();
        public const double BadMs = 3 * 60 * 1000;

        public void Set(Pos p, Cell c, int changeDelta = 0)
        {
            Cells[p] = c;
            if (c == Cell.Change) Changes[p] = changeDelta; else Changes.Remove(p);
        }

        public Cell Get(Pos p) => Cells.TryGetValue(p, out var c) ? c : Cell.Unknown;
        public void MarkBad(Pos p, double now) { Bad[p] = now + BadMs; }
        bool IsBad(Pos p, double now) => Bad.TryGetValue(p, out double until) && until > now;

        static readonly int[] Dx = { 0, 1, 0, -1, 1, 1, -1, -1 }, Dy = { -1, 0, 1, 0, -1, 1, 1, -1 };

        bool Open(Pos p, double now, bool allowChange) { var c = Get(p); return (c == Cell.Walk || (allowChange && c == Cell.Change)) && !IsBad(p, now); }

        /// <summary>A path from `from` to `to` over known walkable tiles on one floor (the last tile may be a floor change when allowChange). Null when none (the node limit counts).</summary>
        public List<Pos> Path(Pos from, Pos to, double now, int maxNodes = 12000, int range = 0)
        {
            if (from.Z != to.Z) return null;
            var open = new SortedSet<(int f, int n, Pos p)>(Comparer<(int f, int n, Pos p)>.Create((a, b) => a.f != b.f ? a.f.CompareTo(b.f) : a.n != b.n ? a.n.CompareTo(b.n) : a.p.X != b.p.X ? a.p.X.CompareTo(b.p.X) : a.p.Y.CompareTo(b.p.Y)));
            var g = new Dictionary<Pos, int> { [from] = 0 };
            var came = new Dictionary<Pos, Pos>();
            var closed = new HashSet<Pos>();
            int n0 = 0;
            open.Add((H(from, to), n0++, from));
            int expanded = 0;
            while (open.Count > 0 && expanded < maxNodes)
            {
                var cur = open.Min;
                open.Remove(cur);
                var p = cur.p;
                if (!closed.Add(p)) continue;
                expanded++;
                if (Math.Max(Math.Abs(p.X - to.X), Math.Abs(p.Y - to.Y)) <= range && (p.X != from.X || p.Y != from.Y || range > 0 || (to.X == from.X && to.Y == from.Y)))
                    return Build(came, p, from);
                for (int i = 0; i < 8; i++)
                {
                    var q = new Pos(p.X + Dx[i], p.Y + Dy[i], p.Z);
                    bool goal = q.X == to.X && q.Y == to.Y;
                    if (closed.Contains(q) || !Open(q, now, goal)) continue;
                    if (i >= 4 && !(Get(new Pos(p.X + Dx[i], p.Y, p.Z)) == Cell.Walk && Get(new Pos(p.X, p.Y + Dy[i], p.Z)) == Cell.Walk)) continue;
                    if (Get(q) == Cell.Change && !goal) continue;
                    int cost = g[p] + (i < 4 ? 10 : 14);
                    if (g.TryGetValue(q, out int old) && old <= cost) continue;
                    g[q] = cost; came[q] = p;
                    open.Add((cost + H(q, to), n0++, q));
                }
            }
            return null;
        }

        static int H(Pos a, Pos b) { int dx = Math.Abs(a.X - b.X), dy = Math.Abs(a.Y - b.Y); return 10 * Math.Max(dx, dy) + 4 * Math.Min(dx, dy); }

        static List<Pos> Build(Dictionary<Pos, Pos> came, Pos end, Pos from)
        {
            var r = new List<Pos> { end };
            while (came.TryGetValue(r[r.Count - 1], out var prev)) r.Add(prev);
            r.Reverse();
            return r;
        }

        /// <summary>The reachable known tiles of `from` (flood fill, 8 directions with the corner rule), with their cost, for the frontier search. Limited to maxNodes.</summary>
        public Dictionary<Pos, int> Reach(Pos from, double now, int maxNodes = 20000)
        {
            var dist = new Dictionary<Pos, int> { [from] = 0 };
            var q = new Queue<Pos>();
            q.Enqueue(from);
            while (q.Count > 0 && dist.Count < maxNodes)
            {
                var p = q.Dequeue();
                for (int i = 0; i < 8; i++)
                {
                    var n = new Pos(p.X + Dx[i], p.Y + Dy[i], p.Z);
                    if (dist.ContainsKey(n) || !Open(n, now, false)) continue;
                    if (i >= 4 && !(Get(new Pos(p.X + Dx[i], p.Y, p.Z)) == Cell.Walk && Get(new Pos(p.X, p.Y + Dy[i], p.Z)) == Cell.Walk)) continue;
                    dist[n] = dist[p] + 1;
                    q.Enqueue(n);
                }
            }
            return dist;
        }

        /// <summary>A reachable tile next to an unknown one (the edge of what was seen).</summary>
        public bool IsFrontier(Pos p)
        {
            for (int i = 0; i < 4; i++) if (Get(new Pos(p.X + Dx[i], p.Y + Dy[i], p.Z)) == Cell.Unknown) return true;
            return false;
        }

        /// <summary>Where to walk next to get toward `goal` (X, Y; the floor of `from`) when the goal is not in the known map or not reachable: among the reachable frontier tiles the one
        /// with the lowest (steps to it + 1.3 x its distance to the goal), skipping tiles in `visitedFrontier`. Null when the known map holds no frontier.</summary>
        public Pos? ExploreToward(Pos from, Pos goal, double now, ISet<Pos> visitedFrontier)
        {
            var reach = Reach(from, now);
            Pos? best = null;
            double bestScore = double.MaxValue;
            foreach (var kv in reach)
            {
                if (kv.Key.X == from.X && kv.Key.Y == from.Y) continue;
                if (visitedFrontier != null && visitedFrontier.Contains(kv.Key)) continue;
                if (!IsFrontier(kv.Key)) continue;
                double score = kv.Value + 1.3 * Math.Max(Math.Abs(kv.Key.X - goal.X), Math.Abs(kv.Key.Y - goal.Y));
                if (score < bestScore) { bestScore = score; best = kv.Key; }
            }
            return best;
        }

        /// <summary>The best known floor change tile that goes the wanted way (+1 down, -1 up): near the character and, when a goal is given, near the goal; else null.</summary>
        public Pos? NearestChange(Pos from, int delta, double now, ISet<Pos> skip, Pos? goal = null)
        {
            Pos? best = null;
            int bestD = int.MaxValue;
            foreach (var kv in Changes)
            {
                if (kv.Value != delta || kv.Key.Z != from.Z) continue;
                if (skip != null && skip.Contains(kv.Key)) continue;
                if (IsBad(kv.Key, now)) continue;
                int d = Math.Max(Math.Abs(kv.Key.X - from.X), Math.Abs(kv.Key.Y - from.Y));
                // a player takes the stair that is on the way to where he wants to go: near him, and near the goal's x and y
                if (goal.HasValue) d += 2 * Math.Max(Math.Abs(kv.Key.X - goal.Value.X), Math.Abs(kv.Key.Y - goal.Value.Y));
                if (d < bestD) { bestD = d; best = kv.Key; }
            }
            return best;
        }
    }

    /// <summary>One step of the planner: the bot's next hop toward a goal, from the map it remembers.</summary>
    public sealed class JourneyPlan
    {
        public enum Kind { Arrived, Walk, Step, Explore, NoWay }
        public Kind What;
        public Pos Target;
        public List<Pos> Path;
        public string Note = "";
    }

    public static class JourneyNav
    {
        /// <summary>The next move toward `goal`: a path on this floor when the goal is known and reachable; else (other floor) the nearest floor change the right way, and the frontier
        /// nearest the goal; else NoWay. `range` is how close counts as arrived.</summary>
        public static JourneyPlan Next(JourneyMap map, Pos from, Pos goal, double now, int range, ISet<Pos> visitedFrontier, ISet<Pos> skipChanges)
        {
            if (from.Z == goal.Z && Math.Max(Math.Abs(from.X - goal.X), Math.Abs(from.Y - goal.Y)) <= range) return new JourneyPlan { What = JourneyPlan.Kind.Arrived, Target = from };
            if (from.Z == goal.Z)
            {
                if (map.Get(goal) == JourneyMap.Cell.Walk || range > 0)
                {
                    var path = map.Path(from, goal, now, 12000, range);
                    if (path != null && path.Count > 1) return new JourneyPlan { What = JourneyPlan.Kind.Walk, Target = path[path.Count - 1], Path = path };
                }
            }
            else
            {
                int delta = goal.Z > from.Z ? 1 : -1;
                var ch = map.NearestChange(from, delta, now, skipChanges, goal);
                if (ch.HasValue)
                {
                    var path = map.Path(from, ch.Value, now);
                    if (path != null && path.Count == 2) return new JourneyPlan { What = JourneyPlan.Kind.Step, Target = ch.Value };
                    if (path != null && path.Count > 2) return new JourneyPlan { What = JourneyPlan.Kind.Walk, Target = path[path.Count - 2], Path = path.GetRange(0, path.Count - 1), Note = "to the floor change at " + ch.Value.X + "," + ch.Value.Y + "," + ch.Value.Z };
                }
            }
            var fr = map.ExploreToward(from, goal, now, visitedFrontier);
            if (fr.HasValue)
            {
                var path = map.Path(from, fr.Value, now);
                if (path != null && path.Count > 1) return new JourneyPlan { What = JourneyPlan.Kind.Explore, Target = fr.Value, Path = path, Note = "frontier " + fr.Value.X + "," + fr.Value.Y };
            }
            return new JourneyPlan { What = JourneyPlan.Kind.NoWay, Note = "no known path and no frontier" };
        }

        /// <summary>The direction of one step from a to the adjacent tile b.</summary>
        public static Dir DirOf(Pos a, Pos b)
        {
            int dx = Math.Sign(b.X - a.X), dy = Math.Sign(b.Y - a.Y);
            if (dx == 0 && dy < 0) return Dir.North;
            if (dx > 0 && dy == 0) return Dir.East;
            if (dx == 0 && dy > 0) return Dir.South;
            if (dx < 0 && dy == 0) return Dir.West;
            if (dx > 0 && dy < 0) return Dir.NorthEast;
            if (dx > 0 && dy > 0) return Dir.SouthEast;
            if (dx < 0 && dy > 0) return Dir.SouthWest;
            return Dir.NorthWest;
        }
    }

    /// <summary>The numbers of one bot: what it did, per hour and per level. Written as JSON (the report tool server/tools/journey_report.py compares minutes per level against the model).</summary>
    public sealed class JourneyMetrics
    {
        public sealed class Death { public string Cause = "", Level = ""; public Pos At; public double AtMin; public int LevelAt; }
        public sealed class StuckEvent { public string What = ""; public Pos At; public double AtMin; public string Hunt = ""; }
        public sealed class Trip { public string Reason = ""; public double AtMin; public int LevelAt; public double Minutes; public long Sold; }

        public string Name = "", Class = "";
        public int Vocation;
        public int StartLevel = 1, Level = 1;
        public long StartExp, Exp;
        public double StartMs = -1, NowMs;
        public int Kills;
        public readonly SortedDictionary<string, int> KillsBy = new SortedDictionary<string, int>(StringComparer.Ordinal);
        /// <summary>Minute (of the run) at which each level was first reached (the start level is minute 0).</summary>
        public readonly SortedDictionary<int, double> LevelAtMin = new SortedDictionary<int, double>();
        public readonly List<Death> Deaths = new List<Death>();
        public readonly List<StuckEvent> Stuck = new List<StuckEvent>();
        public readonly List<Trip> Trips = new List<Trip>();
        public long GoldStart, GoldNow, GoldEarned, GoldSpent;
        public int PotionsUsed, PotionsBought, Reconnects, GaveUpHunts;
        public readonly List<string> Hunts = new List<string>();
        public readonly List<string> Notes = new List<string>();
        public readonly JourneyCoverage Coverage = new JourneyCoverage();
        public string Stop = "";

        public double Minutes => StartMs < 0 ? 0 : Math.Max(0, (NowMs - StartMs) / 60000.0);
        public double Hours => Minutes / 60.0;
        public double KillsPerHour => Hours > 0.0001 ? Kills / Hours : 0;
        public double XpPerHour => Hours > 0.0001 ? (Exp - StartExp) / Hours : 0;
        public double GoldPerHour => Hours > 0.0001 ? GoldEarned / Hours : 0;

        public void Begin(double nowMs, int level, long exp, long gold)
        {
            StartMs = NowMs = nowMs; StartLevel = Level = level; StartExp = Exp = exp; GoldStart = GoldNow = gold;
            LevelAtMin[level] = 0;
        }

        /// <summary>Call every tick with the character's level, experience and gold. A level reached for the first time is stamped (several levels at once get the same minute).</summary>
        public void Observe(double nowMs, int level, long exp, long gold)
        {
            if (StartMs < 0) Begin(nowMs, level, exp, gold);
            NowMs = nowMs; Exp = Math.Max(Exp, exp);
            for (int l = Level + 1; l <= level; l++) if (!LevelAtMin.ContainsKey(l)) LevelAtMin[l] = Minutes;
            Level = Math.Max(Level, level);
            if (gold > GoldNow) GoldEarned += gold - GoldNow;
            else if (gold < GoldNow) GoldSpent += GoldNow - gold;
            GoldNow = gold;
        }

        public void Kill(string monster)
        {
            Kills++;
            string b = JourneyHunts.BaseName(monster);
            KillsBy[b] = KillsBy.TryGetValue(b, out int n) ? n + 1 : 1;
        }

        public void Died(string cause, Pos at) { Deaths.Add(new Death { Cause = cause, At = at, AtMin = Minutes, LevelAt = Level }); }
        public void Stuck_(string what, Pos at, string hunt) { Stuck.Add(new StuckEvent { What = what, At = at, AtMin = Minutes, Hunt = hunt }); }

        /// <summary>Minutes spent on each level that was completed (level L to L+1), from the stamps.</summary>
        public SortedDictionary<int, double> MinutesPerLevel()
        {
            var o = new SortedDictionary<int, double>();
            foreach (var kv in LevelAtMin)
                if (LevelAtMin.TryGetValue(kv.Key + 1, out double next)) o[kv.Key] = Math.Max(0, next - kv.Value);
            return o;
        }

        static string Num(double d) => d.ToString("0.###", CultureInfo.InvariantCulture);

        public Dictionary<string, object> ToJson()
        {
            var perLevel = new Dictionary<string, object>();
            foreach (var kv in MinutesPerLevel()) perLevel[kv.Key.ToString(CultureInfo.InvariantCulture)] = Math.Round(kv.Value, 3);
            var stamps = new Dictionary<string, object>();
            foreach (var kv in LevelAtMin) stamps[kv.Key.ToString(CultureInfo.InvariantCulture)] = Math.Round(kv.Value, 3);
            Func<Pos, object> pos = p => new List<object> { p.X, p.Y, p.Z };
            var deaths = Deaths.Select(d => (object)new Dictionary<string, object> { { "cause", d.Cause }, { "pos", pos(d.At) }, { "minute", Math.Round(d.AtMin, 2) }, { "level", d.LevelAt } }).ToList();
            var stuck = Stuck.Select(d => (object)new Dictionary<string, object> { { "what", d.What }, { "pos", pos(d.At) }, { "minute", Math.Round(d.AtMin, 2) }, { "hunt", d.Hunt } }).ToList();
            var trips = Trips.Select(d => (object)new Dictionary<string, object> { { "reason", d.Reason }, { "minute", Math.Round(d.AtMin, 2) }, { "level", d.LevelAt }, { "minutes", Math.Round(d.Minutes, 2) }, { "sold", d.Sold } }).ToList();
            var kills = new Dictionary<string, object>();
            foreach (var kv in KillsBy) kills[kv.Key] = kv.Value;
            return new Dictionary<string, object>
            {
                { "name", Name }, { "class", Class }, { "vocation", Vocation },
                { "startLevel", StartLevel }, { "level", Level }, { "minutes", Math.Round(Minutes, 2) },
                { "kills", Kills }, { "killsPerHour", Math.Round(KillsPerHour, 1) },
                { "xp", Exp - StartExp }, { "xpPerHour", Math.Round(XpPerHour, 0) },
                { "goldStart", GoldStart }, { "goldNow", GoldNow }, { "goldEarned", GoldEarned }, { "goldSpent", GoldSpent }, { "goldPerHour", Math.Round(GoldPerHour, 0) },
                { "potionsUsed", PotionsUsed }, { "potionsBought", PotionsBought }, { "reconnects", Reconnects }, { "gaveUpHunts", GaveUpHunts },
                { "minutesPerLevel", perLevel }, { "levelAtMinute", stamps },
                { "deaths", deaths }, { "stuck", stuck }, { "trips", trips }, { "killsBy", kills },
                { "hunts", Hunts.Cast<object>().ToList() }, { "notes", Notes.Take(200).Cast<object>().ToList() },
                { "coverage", Coverage.ToJson() }, { "stop", Stop },
            };
        }
    }

    /// <summary>What the bot touched: every system, every client module opcode and every map area, as touched / not touched / failed (with the error).</summary>
    public sealed class JourneyCoverage
    {
        public enum State { NotTouched, Touched, Failed }
        public sealed class Row { public string Group = "", Name = ""; public State What = State.NotTouched; public string Detail = ""; public int Count; public double FirstMin = -1; }

        readonly Dictionary<string, Row> rows = new Dictionary<string, Row>(StringComparer.Ordinal);
        readonly List<string> order = new List<string>();

        public void Declare(string group, string name)
        {
            string k = group + "|" + name;
            if (!rows.ContainsKey(k)) { rows[k] = new Row { Group = group, Name = name }; order.Add(k); }
        }

        public void Touch(string group, string name, double minute, string detail = "")
        {
            Declare(group, name);
            var r = rows[group + "|" + name];
            r.Count++;
            if (r.FirstMin < 0) r.FirstMin = minute;
            r.What = State.Touched;
            if (detail.Length > 0 && r.Detail.Length == 0) r.Detail = detail;
        }

        public void Fail(string group, string name, double minute, string error)
        {
            Declare(group, name);
            var r = rows[group + "|" + name];
            r.Count++;
            r.What = State.Failed;
            r.Detail = error ?? "";
            if (r.FirstMin < 0) r.FirstMin = minute;
        }

        public IEnumerable<Row> Rows => order.Select(k => rows[k]);
        public Row Get(string group, string name) => rows.TryGetValue(group + "|" + name, out var r) ? r : null;
        public int Count(string group, State s) => Rows.Count(r => r.Group == group && r.What == s);

        public static string StateName(State s) => s == State.Touched ? "touched" : s == State.Failed ? "failed" : "not touched";

        public List<object> ToJson() =>
            Rows.Select(r => (object)new Dictionary<string, object> { { "group", r.Group }, { "name", r.Name }, { "state", StateName(r.What) }, { "count", r.Count }, { "firstMinute", Math.Round(r.FirstMin, 2) }, { "detail", r.Detail } }).ToList();

        /// <summary>The coverage table as text: one block per group.</summary>
        public string Table()
        {
            var sb = new StringBuilder();
            foreach (var g in Rows.Select(r => r.Group).Distinct())
            {
                sb.Append(g).Append(": ").Append(Count(g, State.Touched)).Append(" touched, ").Append(Count(g, State.NotTouched)).Append(" not touched, ").Append(Count(g, State.Failed)).Append(" failed\n");
                foreach (var r in Rows.Where(x => x.Group == g))
                    sb.Append("  ").Append(r.Name).Append(": ").Append(StateName(r.What)).Append(r.Detail.Length > 0 ? " (" + r.Detail + ")" : "").Append('\n');
            }
            return sb.ToString();
        }
    }
}
