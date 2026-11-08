// The combat helper's decisions as pure functions and small state machines. A port of the main client's
//   game_helper/helper_logic.lua      (areas, target modes A..H, the healing / training / haste rows, the shooter slots)
//   game_helper/helper_potions.lua    (the potion list, which potion goes out)
//   game_helpertimers/helpertimers.lua (a rate guard per cast channel, a timer per object use)
//   game_helperrotation/rotation.lua  (cast bookkeeping: a cast waits for the server's cooldown packet, refused casts back off)
// Positions are Pos (X, Y, Z). Tests: Core.Tests/HelperTests.cs mirrors helper_logic_test.lua, rotation_test.lua, helper_potions_test.lua.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>A creature the helper may shoot at: id, position, health percent and, for target mode E, how many others an area on it hits.</summary>
    public struct HelperCreature
    {
        public uint Id;
        public Pos Position;
        public int Health;
        public int Hits;
        public HelperCreature(uint id, Pos p, int health, int hits = 0) { Id = id; Position = p; Health = health; Hits = hits; }
    }

    public static class HelperLogic
    {
        public const double HasteGapMs = 2500;       // a haste cast waits at least this long after the last one
        public const double HasteMaxGapMs = 120000;  // the wait doubles per cast in a row that gave no haste, up to this
        public const int ReachX = 7, ReachY = 5;     // the shooter and Auto Target look this far (half width, half height) around the player

        // ------------------------------------------------------------------------------------ areas
        /// <summary>Area cells: 1 hit, 2 or 3 the caster's own cell (3: the spell also hits there), 0 empty. Rows go north to south.
        /// The area faces north; South, East and West turn it, any other facing leaves it.</summary>
        public static int[][] RotateArea(int[][] area, Dir direction)
        {
            if (area == null || area.Length == 0 || area[0] == null) return area;
            int rows = area.Length, cols = area[0].Length;
            int[][] o;
            switch (direction)
            {
                case Dir.South:
                    o = new int[rows][];
                    for (int y = 0; y < rows; y++) { o[y] = new int[cols]; for (int x = 0; x < cols; x++) o[y][x] = area[rows - 1 - y][cols - 1 - x]; }
                    return o;
                case Dir.East:
                    o = new int[cols][];
                    for (int x = 0; x < cols; x++) { o[x] = new int[rows]; for (int y = 0; y < rows; y++) o[x][y] = area[rows - 1 - y][x]; }
                    return o;
                case Dir.West:
                    o = new int[cols][];
                    for (int x = 0; x < cols; x++) { o[x] = new int[rows]; for (int y = 0; y < rows; y++) o[x][y] = area[y][cols - 1 - x]; }
                    return o;
                default: return area;
            }
        }

        public static int[][] ToMatrix(List<List<int>> area)
        {
            if (area == null || area.Count == 0) return null;
            var o = new int[area.Count][];
            for (int i = 0; i < o.Length; i++) o[i] = area[i].ToArray();
            return o;
        }

        public static bool FindCaster(int[][] area, out int cx, out int cy)
        {
            for (int y = 0; y < area.Length; y++)
                for (int x = 0; x < area[y].Length; x++)
                    if (area[y][x] == 3 || area[y][x] == 2) { cx = x; cy = y; return true; }
            cx = cy = -1;
            return false;
        }

        static Dir Cardinal(Dir d)
        {
            if (d == Dir.NorthEast || d == Dir.SouthEast) return Dir.East;
            if (d == Dir.SouthWest || d == Dir.NorthWest) return Dir.West;
            return d;
        }

        /// <summary>How many creatures the area hits cast from `from` facing `direction`. ranged: the caster's own cell counts.
        /// sight(from, to) says whether the line is clear (a creature next to the caster needs none); null: always clear.</summary>
        public static int CountHits(Pos from, Dir direction, int[][] area, IList<HelperCreature> creatures, bool ranged = false, Func<Pos, Pos, bool> sight = null)
        {
            var rotated = RotateArea(area, Cardinal(direction));
            if (rotated == null || !FindCaster(rotated, out int cx, out int cy)) return 0;
            var seen = new HashSet<uint>();
            int n = 0;
            for (int yy = 0; yy < rotated.Length; yy++)
                for (int xx = 0; xx < rotated[yy].Length; xx++)
                {
                    int v = rotated[yy][xx];
                    if (!(v == 1 || (ranged && (v == 2 || v == 3)))) continue;
                    int px = from.X + (xx - cx), py = from.Y + (yy - cy);
                    foreach (var c in creatures)
                    {
                        var p = c.Position;
                        if (p.X != px || p.Y != py || p.Z != from.Z || seen.Contains(c.Id)) continue;
                        bool near = Math.Abs(from.X - p.X) <= 1 && Math.Abs(from.Y - p.Y) <= 1;
                        if (near || sight == null || sight(from, p)) { seen.Add(c.Id); n++; break; }
                    }
                }
            return n;
        }

        /// <summary>The facing that hits most (North, East, South, West tried in that order, the first best wins). hits 0: no facing hits anything.</summary>
        public static Dir BestDirection(Pos from, int[][] area, IList<HelperCreature> creatures, out int hits, Func<Pos, Pos, bool> sight = null)
        {
            Dir best = Dir.North;
            int bestN = 0;
            foreach (var d in new[] { Dir.North, Dir.East, Dir.South, Dir.West })
            {
                int n = CountHits(from, d, area, creatures, false, sight);
                if (n > bestN) { best = d; bestN = n; }
            }
            hits = bestN;
            return best;
        }

        public static bool InReach(Pos from, Pos pos)
        {
            return from.Z == pos.Z && Math.Abs(from.X - pos.X) <= ReachX && Math.Abs(from.Y - pos.Y) <= ReachY;
        }

        public static int Distance(Pos a, Pos b) => Math.Max(Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));

        // ------------------------------------------------------------------------------------ target modes
        public const int ModeClosest = 1, ModeFarthest = 2, ModeLowest = 3, ModeHighest = 4, ModeHits = 5, ModeClosestLowest = 6,
            ModeClosestHighest = 7, ModeFarthestLowest = 8;
        public const int ModeDefault = 6, ModeMax = 8;
        public static readonly string[] ModeKeys = { "A", "B", "C", "D", "E", "F", "G", "H" };

        static double[] Keys(int mode, int d, int h, int n, long id)
        {
            switch (mode)
            {
                case ModeClosest: return new double[] { d, id };
                case ModeFarthest: return new double[] { -d, id };
                case ModeLowest: return new double[] { h, d, id };
                case ModeHighest: return new double[] { -h, d, id };
                case ModeHits: return new double[] { -n, d, h, id };
                case ModeClosestHighest: return new double[] { d, -h, id };
                case ModeFarthestLowest: return new double[] { -d, h, id };
                default: return new double[] { d, h, id };
            }
        }

        /// <summary>The creature to attack by mode A..H (1..8). A tie goes to the nearer one, then to the lower id, so the choice does not
        /// flicker between two equal monsters. Returns false when there is no candidate.</summary>
        public static bool PickByMode(IList<HelperCreature> candidates, Pos from, int mode, out HelperCreature pick)
        {
            pick = default(HelperCreature);
            double[] bestKeys = null;
            bool any = false;
            if (mode < 1 || mode > ModeMax) mode = ModeDefault;
            foreach (var c in candidates)
            {
                var k = Keys(mode, Distance(from, c.Position), c.Health, c.Hits, c.Id);
                bool better = !any;
                if (any)
                    for (int i = 0; i < k.Length; i++)
                        if (k[i] != bestKeys[i]) { better = k[i] < bestKeys[i]; break; }
                if (better) { pick = c; bestKeys = k; any = true; }
            }
            return any;
        }

        // ------------------------------------------------------------------------------------ the rows
        /// <summary>The healing spell to cast now (0: none). The lowest threshold goes first: the strongest heal for the lowest health.
        /// ready(id): the spell can go out (castable, off cooldown, enough mana).</summary>
        public static int PickHeal(IList<HelperHealRow> rows, double healthPct, Func<int, bool> ready = null)
        {
            int best = 0, bestPercent = int.MaxValue;
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                if (r.Id <= 0 || healthPct > r.Percent || (ready != null && !ready(r.Id))) continue;
                if (r.Percent < bestPercent) { best = r.Id; bestPercent = r.Percent; }   // a tie keeps the first row
            }
            return best;
        }

        public static bool TrainingDue(HelperTrainRow row, double manaPct) => row != null && row.Enabled && row.Id > 0 && manaPct >= row.Percent;

        /// <summary>The wait after the last Auto Haste cast: HasteGapMs, doubled per cast in a row that gave no haste, up to HasteMaxGapMs.</summary>
        public static double HasteGap(int misses) => Math.Min(HasteGapMs * Math.Pow(2, Math.Max(misses, 0)), HasteMaxGapMs);

        /// <summary>Auto Haste bookkeeping: Observe every tick, Cast when a cast went out. A cast not followed by the Haste state counts as a
        /// miss (a retired haste spell was said twice a second for minutes); the haste showing resets it.</summary>
        public sealed class HasteState
        {
            public double Last = -1;
            public int Misses;
            public bool Seen;
            public void Observe(bool hasted) { if (hasted) { Misses = 0; Seen = true; } }
            public void Cast(double now) { if (Last >= 0 && !Seen) Misses++; Last = now; Seen = false; }
        }

        public static bool HasteDue(HelperHasteRow row, bool hasted, double now, double last, int misses, bool inProtectionZone)
        {
            if (row == null || !row.Enabled || row.Id <= 0) return false;
            if (hasted) return false;
            if (inProtectionZone && !row.SafeCast) return false;
            if (last >= 0 && now - last < HasteGap(misses)) return false;
            return true;
        }

        /// <summary>A shooter slot is due: the mana is at or above its percent and its creature count is met.</summary>
        public static bool SlotDue(HelperSlot slot, double manaPct, int hits)
        {
            if (slot == null || slot.Id <= 0) return false;
            if (manaPct < slot.Percent) return false;
            return hits >= slot.Creatures;
        }

        /// <summary>The facing from `from` toward `to` for an aimed wave: the longer axis. False on the same tile or another floor; a tie goes vertical.</summary>
        public static bool FacingToward(Pos from, Pos to, out Dir dir)
        {
            dir = Dir.North;
            if (from.Z != to.Z) return false;
            int dx = to.X - from.X, dy = to.Y - from.Y;
            if (dx == 0 && dy == 0) return false;
            if (Math.Abs(dx) > Math.Abs(dy)) dir = dx > 0 ? Dir.East : Dir.West;
            else dir = dy > 0 ? Dir.South : Dir.North;
            return true;
        }

        /// <summary>The slots in the order they are tried (priority, then position); empty slots are left out.</summary>
        public static List<HelperSlot> SlotOrder(IList<HelperSlot> slots)
        {
            var list = new List<KeyValuePair<int, HelperSlot>>();
            for (int i = 0; i < slots.Count; i++) if (slots[i] != null && slots[i].Id > 0) list.Add(new KeyValuePair<int, HelperSlot>(i, slots[i]));
            list.Sort((a, b) =>
            {
                int pa = a.Value.Priority > 0 ? a.Value.Priority : a.Key + 1, pb = b.Value.Priority > 0 ? b.Value.Priority : b.Key + 1;
                return pa != pb ? pa.CompareTo(pb) : a.Key.CompareTo(b.Key);
            });
            var o = new List<HelperSlot>();
            foreach (var e in list) o.Add(e.Value);
            return o;
        }

        // ------------------------------------------------------------------------------------ auto turn (rotation.lua)
        /// <summary>The cardinal facing from one position toward another. A diagonal keeps the current facing when it is one of the two
        /// sides (a wave covers both), else the vertical one. False on the same tile or another floor.</summary>
        public static bool DirToward(Pos from, Pos to, Dir facing, out Dir dir)
        {
            dir = Dir.North;
            if (from.Z != to.Z) return false;
            int dx = to.X - from.X, dy = to.Y - from.Y;
            if (dx == 0 && dy == 0) return false;
            Dir horizontal = dx > 0 ? Dir.East : Dir.West, vertical = dy > 0 ? Dir.South : Dir.North;
            if (dx == 0) dir = vertical;
            else if (dy == 0) dir = horizontal;
            else if (Math.Abs(dx) > Math.Abs(dy)) dir = horizontal;
            else if (Math.Abs(dy) > Math.Abs(dx)) dir = vertical;
            else dir = (facing == horizontal || facing == vertical) ? facing : vertical;
            return true;
        }

        /// <summary>The facing to turn to before casting a directional spell, or false (leave it): the option is off, the spell is not
        /// directional, the character already faces that way. With a target the character faces it, without one the facing with most monsters.</summary>
        public static bool TurnDirection(bool directional, bool enabled, Dir facing, Pos from, bool hasTarget, Pos target, bool hasBest, Dir best, out Dir turn)
        {
            turn = facing;
            if (!enabled || !directional) return false;
            bool want = false;
            Dir d = Dir.North;
            if (hasTarget) want = DirToward(from, target, facing, out d);
            if (!want && hasBest) { d = best; want = true; }
            if (!want || d == facing) return false;
            turn = d;
            return true;
        }

        // ------------------------------------------------------------------------------------ what the spell can do (rotation.lua)
        /// <summary>A spell the client can tell it cannot cast: level and mana, and a Monk finisher without its chi (chi null = unknown).</summary>
        public static bool Castable(Spell s, int level, int mana, int maxMana, int? chi = null)
        {
            if (s == null) return false;
            int need;
            if (HelperCasts.FinisherChi.TryGetValue(s.Id, out need) && chi.HasValue && chi.Value < need) return false;
            if (s.Level > 0 && level > 0 && level < s.Level) return false;
            int cost = s.Mana;
            if (cost <= 0 && s.ManaPercent > 0) cost = (int)Math.Ceiling(maxMana * s.ManaPercent / 100.0);
            if (cost > 0 && mana < cost) return false;
            return true;
        }

        /// <summary>The spell needs a creature to aim at: the server's list marks its centre as the target, or it is a single-target spell.</summary>
        public static bool NeedsTarget(Spell s) => s.Center == "target" || s.Target == "single";

        /// <summary>A wave or beam: it hits along the caster's facing (the server's list marks it "front").</summary>
        public static bool IsDirectional(Spell s) => s.Target == "front" && !NeedsTarget(s);

        /// <summary>An attack centred on the caster with no area table (the Chaos spells such as Reaping Gyre): it needs a monster close by.</summary>
        public static bool IsSelfArea(Spell s) => s.Area.Count == 0 && !NeedsTarget(s) && s.Range <= 0 && s.Group == 1;

        public static int CountNear(IList<HelperCreature> list, Pos pos, int radius)
        {
            int n = 0;
            foreach (var c in list) if (c.Position.Z == pos.Z && Distance(c.Position, pos) <= radius) n++;
            return n;
        }

        /// <summary>The cooldown channel of a spell: healing group -> "heal", attack or special -> "attack", anything else -> "support".</summary>
        public static string Channel(Spell s) => s.Group == 2 ? HelperTimers.Heal : (s.Group == 1 || s.Group == 4) ? HelperTimers.Attack : HelperTimers.Support;
    }

    // ---------------------------------------------------------------------------------------- cooldown channels (helpertimers.lua)
    /// <summary>Each cast channel (heal, attack, support) has its own rate guard, each object use (potion) its own timer, so a heal and an
    /// attack never wait for each other and the helper never floods the server.</summary>
    public sealed class HelperTimers
    {
        public const string Heal = "heal", Attack = "attack", Support = "support";
        public const string Potion = "potion";

        sealed class Guard { public double SameWordsGap; public int MaxPerSecond; public readonly Dictionary<string, double> Last = new Dictionary<string, double>(); public readonly List<double> Recent = new List<double>(); }
        readonly Dictionary<string, Guard> casts = new Dictionary<string, Guard>
        {
            { Heal, new Guard { SameWordsGap = 500, MaxPerSecond = 4 } },
            { Attack, new Guard { SameWordsGap = 500, MaxPerSecond = 4 } },
            { Support, new Guard { SameWordsGap = 500, MaxPerSecond = 3 } },
        };
        // the server's potion channel is 500 ms; the helper waits 100 ms more (two uses a little under the server's delay apart were refused)
        readonly Dictionary<string, double> useGap = new Dictionary<string, double> { { Potion, 600 } };
        readonly Dictionary<string, double> uses = new Dictionary<string, double>();

        /// <summary>May this cast go out now? Records it when it may. An unknown channel counts as support.</summary>
        public bool CastAllowed(string channel, string words, double now)
        {
            Guard g;
            if (!casts.TryGetValue(channel ?? "", out g)) g = casts[Support];
            g.Recent.RemoveAll(t => now - t >= 1000);
            double last;
            bool has = words != null && g.Last.TryGetValue(words, out last);
            last = has ? g.Last[words] : 0;
            if (g.Recent.Count >= g.MaxPerSecond || (has && now - last < g.SameWordsGap)) return false;
            if (words != null) g.Last[words] = now;
            g.Recent.Add(now);
            return true;
        }

        public bool UseReady(string channel, double now) { double t; return !uses.TryGetValue(channel, out t) || t <= now; }

        public void Used(string channel, double now, double ms = -1)
        {
            double d = ms >= 0 ? ms : (useGap.TryGetValue(channel, out var g) ? g : 1000);
            uses[channel] = now + d;
        }

        public void Reset()
        {
            foreach (var g in casts.Values) { g.Last.Clear(); g.Recent.Clear(); }
            uses.Clear();
        }
    }

    // ---------------------------------------------------------------------------------------- cast bookkeeping (rotation.lua)
    /// <summary>A cast waits for the server's answer (the cooldown packet of the spell or of its group). Until then the spell is not sent again
    /// and its group is held for about two round trips. No answer within the confirm window means refused: the spell backs off (2 s, 4 s,
    /// 8 s, at most 16 s) and the rest of the rotation goes on. An answer ends the back-off at once.</summary>
    public sealed class HelperCasts
    {
        public double ConfirmMs = 1200, HoldMinMs = 250, HoldMaxMs = 1200, BackoffMs = 2000, BackoffMaxMs = 16000;
        public const int SelfAreaRadius = 3;
        /// <summary>Cast-time spells (server data/lib/chaos_casting.lua): another attack meanwhile interrupts the cast. Spell id -> ms.</summary>
        public static readonly Dictionary<int, int> CastMs = new Dictionary<int, int> { { 206, 1500 }, { 213, 1500 }, { 219, 1000 }, { 225, 1000 }, { 146, 2000 } };
        /// <summary>The Monk finishers spend all chi: spell id -> chi needed (the measured rotation).</summary>
        public static readonly Dictionary<int, int> FinisherChi = new Dictionary<int, int> { { 64, 4 }, { 65, 4 }, { 69, 4 }, { 71, 4 }, { 66, 1 }, { 70, 1 } };

        sealed class Pending { public double At; public HashSet<int> Groups; }
        readonly Dictionary<int, Pending> pending = new Dictionary<int, Pending>();
        readonly Dictionary<int, int> fails = new Dictionary<int, int>();
        readonly Dictionary<int, double> backoff = new Dictionary<int, double>();
        readonly Dictionary<int, double> settled = new Dictionary<int, double>();
        double channelUntil = -1;
        public double Rtt = -1;
        public int Refused, Confirmed;

        public bool IsPending(int id) => pending.ContainsKey(id);
        public double BackoffUntil(int id) { double v; return backoff.TryGetValue(id, out v) ? v : 0; }
        public int Fails(int id) { int v; return fails.TryGetValue(id, out v) ? v : 0; }

        double ConfirmWindow() => Rtt >= 0 && Rtt * 3 > ConfirmMs ? Rtt * 3 : ConfirmMs;
        double HoldWindow()
        {
            double h = Rtt >= 0 ? 2 * Rtt + 100 : HoldMaxMs;
            return Math.Min(Math.Max(h, HoldMinMs), HoldMaxMs);
        }

        /// <summary>Unanswered casts older than the confirm window were refused: back that spell off. Returns the ids.</summary>
        public List<int> Expire(double now)
        {
            List<int> refused = null;
            double window = ConfirmWindow();
            foreach (var id in new List<int>(pending.Keys))
            {
                if (now - pending[id].At < window) continue;
                pending.Remove(id);
                int n = Fails(id) + 1;
                fails[id] = n;
                backoff[id] = now + Math.Min(BackoffMs * Math.Pow(2, n - 1), BackoffMaxMs);
                Refused++;
                if (refused == null) refused = new List<int>();
                refused.Add(id);
            }
            return refused ?? new List<int>();
        }

        /// <summary>Why `id` may not go out now: "backoff", "pending" (its own cast waits for the answer), "group" (another cast of one of its
        /// groups waits for the answer), or null when free. holdGroups false skips the group rule (healing: a refused big heal must not keep a small one back).</summary>
        public string Blocked(int id, IEnumerable<int> groups, double now, bool holdGroups = true)
        {
            Expire(now);
            double b;
            if (backoff.TryGetValue(id, out b))
            {
                if (b > now) return "backoff";
                backoff.Remove(id);
            }
            if (pending.ContainsKey(id)) return "pending";
            if (holdGroups)
            {
                double hold = HoldWindow();
                var mine = new List<int>(groups ?? new int[0]);
                foreach (var kv in pending)
                {
                    if (kv.Key == id || now - kv.Value.At >= hold) continue;
                    foreach (int g in mine) if (kv.Value.Groups.Contains(g)) return "group";
                }
            }
            return null;
        }

        public void Cast(int id, IEnumerable<int> groups, double now)
        {
            pending[id] = new Pending { At = now, Groups = new HashSet<int>(groups ?? new int[0]) };
            int ms;
            if (CastMs.TryGetValue(id, out ms)) channelUntil = now + ms + HoldWindow();
        }

        /// <summary>A cast-time spell of ours is still charging.</summary>
        public bool Channeling(double now) => channelUntil >= 0 && now < channelUntil;

        void Settle(int id, double now)
        {
            Pending p;
            if (pending.TryGetValue(id, out p))
            {
                double d = now - p.At;
                if (d >= 0) Rtt = Rtt >= 0 ? Math.Floor(Rtt * 0.75 + d * 0.25) : d;
                Confirmed++;
                foreach (int g in p.Groups) { double s; if (!settled.TryGetValue(g, out s) || s < p.At) settled[g] = p.At; }
            }
            pending.Remove(id); fails.Remove(id); backoff.Remove(id);
        }

        /// <summary>The server's cooldown packet for a spell (0xA4): its cast went through.</summary>
        public void ConfirmSpell(int id, double now) { Settle(id, now); }

        /// <summary>The server's group cooldown packet (0xA5): it answers the latest cast of that group (a refused cast before it gets none).</summary>
        public void ConfirmGroup(int group, double now)
        {
            double window = ConfirmWindow();
            int latest = -1;
            double at = -1;
            foreach (var kv in pending)
                if (kv.Value.Groups.Contains(group) && now - kv.Value.At < window && (at < 0 || kv.Value.At > at)) { latest = kv.Key; at = kv.Value.At; }
            double s;
            if (latest >= 0 && !(settled.TryGetValue(group, out s) && s >= at)) Settle(latest, now);
        }
    }

    // ---------------------------------------------------------------------------------------- potions (helper_potions.lua)
    public sealed class HelperPotion
    {
        public int Id, Level;
        public string Name = "", Kind = "health";   // health | mana | both (the spirit potions give both)
        public HelperPotion(int id, string name, string kind, int level) { Id = id; Name = name; Kind = kind; Level = level; }
    }

    public static class HelperPotions
    {
        // client ids; every class drinks every potion, only the level gates stay (server/tools/patch_open_potions.py).
        // The Everfull flasks have a look of their own since pair 44 (client items 38645-38656), one per slot, never used up.
        public static readonly List<HelperPotion> List = new List<HelperPotion>
        {
            new HelperPotion(23375, "Supreme Health Potion", "health", 200), new HelperPotion(23374, "Ultimate Spirit Potion", "both", 130),
            new HelperPotion(7643, "Ultimate Health Potion", "health", 130), new HelperPotion(7642, "Great Spirit Potion", "both", 80),
            new HelperPotion(239, "Great Health Potion", "health", 80), new HelperPotion(236, "Strong Health Potion", "health", 50),
            new HelperPotion(266, "Health Potion", "health", 1), new HelperPotion(7876, "Small Health Potion", "health", 1),
            new HelperPotion(23373, "Ultimate Mana Potion", "mana", 130), new HelperPotion(238, "Great Mana Potion", "mana", 80),
            new HelperPotion(237, "Strong Mana Potion", "mana", 50), new HelperPotion(268, "Mana Potion", "mana", 1),
            new HelperPotion(38645, "Everfull Health Potion", "health", 0), new HelperPotion(38646, "Everfull Great Health Potion", "health", 80),
            new HelperPotion(38647, "Everfull Ultimate Health Potion", "health", 130), new HelperPotion(38648, "Everfull Supreme Health Potion", "health", 200),
            new HelperPotion(38649, "Everfull Mana Potion", "mana", 0), new HelperPotion(38650, "Everfull Great Mana Potion", "mana", 80),
            new HelperPotion(38651, "Everfull Ultimate Mana Potion", "mana", 130), new HelperPotion(38652, "Everfull Supreme Mana Potion", "mana", 200),
            new HelperPotion(38653, "Everfull Spirit Potion", "both", 0), new HelperPotion(38654, "Everfull Great Spirit Potion", "both", 80),
            new HelperPotion(38655, "Everfull Ultimate Spirit Potion", "both", 130), new HelperPotion(38656, "Everfull Supreme Spirit Potion", "both", 200),
        };

        public static HelperPotion Info(int id) { foreach (var p in List) if (p.Id == id) return p; return null; }

        public static bool CanDrink(int id, int level) { var p = Info(id); return p != null && level >= p.Level; }

        /// <summary>What a row heals: a spirit potion follows the row's priority (1 health, 2 mana; unset: health). Null for an unknown item.</summary>
        public static string RowKind(HelperPotionRow row)
        {
            var p = Info(row.Id);
            if (p == null) return null;
            return p.Kind == "both" ? (row.Priority == 2 ? "mana" : "health") : p.Kind;
        }

        static List<HelperPotionRow> Due(IList<HelperPotionRow> rows, string kind, double pct, Func<int, bool> available)
        {
            var list = new List<KeyValuePair<int, HelperPotionRow>>();
            for (int i = 0; i < rows.Count; i++)
            {
                var r = rows[i];
                if (r.Id > 0 && RowKind(r) == kind && pct <= r.Percent && (available == null || available(r.Id))) list.Add(new KeyValuePair<int, HelperPotionRow>(i, r));
            }
            list.Sort((a, b) =>
            {
                if (a.Value.Percent != b.Value.Percent) return a.Value.Percent.CompareTo(b.Value.Percent);
                if (a.Value.Priority != b.Value.Priority) return a.Value.Priority.CompareTo(b.Value.Priority);
                return a.Key.CompareTo(b.Key);
            });
            var o = new List<HelperPotionRow>();
            foreach (var e in list) o.Add(e.Value);
            return o;
        }

        /// <summary>The potion to drink now (0: none), health before mana, the lowest threshold first. kind says which pool.</summary>
        public static int Pick(IList<HelperPotionRow> rows, double healthPct, double manaPct, Func<int, bool> available, out string kind)
        {
            var h = Due(rows, "health", healthPct, available);
            if (h.Count > 0) { kind = "health"; return h[0].Id; }
            var m = Due(rows, "mana", manaPct, available);
            if (m.Count > 0) { kind = "mana"; return m[0].Id; }
            kind = null;
            return 0;
        }

        /// <summary>A health potion row is due by the numbers alone (its potion may not be at hand): the mana potions wait for it.</summary>
        public static bool HealthDue(IList<HelperPotionRow> rows, double healthPct) => Due(rows, "health", healthPct, null).Count > 0;
    }
}
