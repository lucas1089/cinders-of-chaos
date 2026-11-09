// Phase 7 track X, helper: the parts the first helper ports left out. Ports of game_helper (helper_follow.lua, helper_sell.lua, the exercise
// weapon tick of helper.lua, the line-of-sight check `g_map.isSightClear`), game_helperrotation (potiongate.lua: potions and runes in closed
// backpacks; autorotation.lua levelUpAction and merge: the level-up notice). Pure rules here, tested in Core.Tests/Phase7XTests.cs; the engine
// glue is the partial HelperEngine at the end of this file and Unity/Windows/HelperWindowP7.cs.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    // ============================================================================================================ settings
    /// <summary>Follow a friend by name or the party leader (the `follow` section of helper_config.lua).</summary>
    public sealed class HelperFollowCfg
    {
        public const int DistanceMax = 5;
        public bool Enabled;
        /// <summary>"name" (a friend by name) or "leader" (the player with the leader shield).</summary>
        public string Mode = "name";
        public string Name = "";
        public int Distance = 1;
    }

    /// <summary>Ask the Auto Seller to sell the Loot Bag (the `autoSell` section).</summary>
    public sealed class HelperSellCfg
    {
        public const int CapacityMax = 100000;
        public static readonly int[] Minutes = { 5, 10, 15, 30, 60 };
        public bool Enabled;
        public int Interval = 30;
        public bool BelowCap;
        public int Capacity = 100;
        public static int MinutesOf(double v) { foreach (int m in Minutes) if (v == m) return m; return -1; }
    }

    /// <summary>Use an exercise weapon on a training dummy while standing in a protection zone (the `exercise` section).</summary>
    public sealed class HelperExerciseCfg
    {
        public bool Enabled;
        /// <summary>The exercise weapon's client id, 0 for any one you carry.</summary>
        public int Id;
    }

    // ============================================================================================================ follow
    public sealed class FollowState
    {
        public double LastAsk = -1, HoldUntil;
        public int Fails;
        public bool Ours;
    }

    public struct FollowInput
    {
        public bool HelperOn, Pz;
        /// <summary>The leader in view (null: out of view).</summary>
        public HelperPlayer Leader;
        public Pos From;
        /// <summary>The creature followed now (0: none).</summary>
        public uint Following;
        public double Now;
    }

    public static class HelperFollow
    {
        public const double AskGapMs = 250, RetryMs = 5000;
        public const int FailMax = 5;

        /// <summary>The leader among the players in view: the friend by name, or the one with the party leader shield. Never yourself.</summary>
        public static HelperPlayer LeaderOf(HelperFollowCfg cfg, IList<HelperPlayer> players)
        {
            if (cfg == null || players == null) return null;
            string want = null;
            if (cfg.Mode != "leader")
            {
                want = HelperAlly.CleanName(cfg.Name);
                if (want == null) return null;
                want = want.ToLowerInvariant();
            }
            foreach (var p in players)
            {
                if (p.IsSelf) continue;
                if (want != null) { if (p.Name != null && p.Name.ToLowerInvariant() == want) return p; }
                else if (HelperAlly.IsLeaderShield(p.Shield)) return p;
            }
            return null;
        }

        /// <summary>What to do now: "follow", "release" or null, and the reason (for the status line and the tests). The state keeps what the helper asked for.</summary>
        public static string Decide(HelperFollowCfg cfg, FollowState st, FollowInput inp, out string why)
        {
            if (cfg == null || !cfg.Enabled)
            {
                if (st.Ours && inp.Following != 0) { st.Ours = false; why = "off"; return "release"; }
                st.Ours = false; why = "off"; return null;
            }
            if (!inp.HelperOn) { why = "helperoff"; return null; }
            if (inp.Pz) { why = "pz"; return null; }
            var leader = inp.Leader;
            if (leader == null || leader.Position.Z != inp.From.Z || !HelperLogic.InReach(inp.From, leader.Position))
            {
                // out of view or on another floor: let our own follow go, never chase the old spot
                if (st.Ours && inp.Following != 0) { st.Ours = false; why = "away"; return "release"; }
                st.Ours = false; why = "away"; return null;
            }
            int distance = Math.Max(1, Math.Min(HelperFollowCfg.DistanceMax, cfg.Distance));
            int dist = HelperLogic.Distance(inp.From, leader.Position);
            bool followingLeader = inp.Following != 0 && inp.Following == leader.Id;
            if (followingLeader)
            {
                st.Fails = 0; st.Ours = true;
                if (distance > 1 && dist <= distance) { st.Ours = false; why = "near"; return "release"; }
                why = "following"; return null;
            }
            // not following the leader (nothing, or somebody else the player chose by hand: that is left alone)
            if (inp.Following != 0 && !st.Ours) { why = "other"; return null; }
            if (distance > 1 && dist <= distance + 1) { why = "near"; return null; }
            if (dist <= 1 && distance <= 1) { why = "adjacent"; return null; }
            if (inp.Now < st.HoldUntil) { why = "retry"; return null; }
            if (st.LastAsk >= 0 && inp.Now - st.LastAsk < AskGapMs) { why = "gap"; return null; }
            st.LastAsk = inp.Now;
            st.Fails++;
            if (st.Fails > FailMax) { st.Fails = 0; st.HoldUntil = inp.Now + RetryMs; why = "giveup"; return null; }
            st.Ours = true;
            why = "ask";
            return "follow";
        }
    }

    // ============================================================================================================ auto sell
    public sealed class SellState
    {
        public double LastAsk = -1, LastSync = -1, Start = -1;
    }

    public struct SellerView
    {
        public bool Known, Unlocked;
        /// <summary>Seconds of the server's cooldown left.</summary>
        public int Cooldown;
    }

    public static class HelperSell
    {
        public const double CapGapMs = 60000, MinGapMs = 31000, StateStaleMs = 300000;

        /// <summary>"sell", "sync" or null, and the reason. Asks only when the server told the client the Auto Seller is unlocked and its cooldown is over, outside the pauses
        /// the helper has anyway; the server decides what is sold. every `Interval` minutes after the last ask, or when the free capacity is at or under `Capacity` oz.</summary>
        public static string Decide(HelperSellCfg cfg, SellState st, SellerView seller, double now, double freeCap, bool helperOn, out string why)
        {
            if (cfg == null || !cfg.Enabled) { why = "off"; return null; }
            if (!helperOn) { why = "helperoff"; return null; }
            if (!seller.Known)
            {
                if (st.LastSync < 0 || now - st.LastSync >= 10000) { st.LastSync = now; why = "unknown"; return "sync"; }
                why = "unknown"; return null;
            }
            if (!seller.Unlocked)
            {
                if (st.LastSync < 0 || now - st.LastSync >= StateStaleMs) { st.LastSync = now; why = "locked"; return "sync"; }
                why = "locked"; return null;
            }
            if (seller.Cooldown > 0) { why = "cooldown"; return null; }
            if (st.LastAsk >= 0 && now - st.LastAsk < MinGapMs) { why = "gap"; return null; }
            int minutes = HelperSellCfg.MinutesOf(cfg.Interval) > 0 ? cfg.Interval : 30;
            double since = st.LastAsk;
            if (since < 0)
            {
                if (st.Start < 0) st.Start = now;
                since = st.Start;   // before the first ask the count runs from the first look at the state: no sale at the very login
            }
            bool due = now - since >= minutes * 60000.0;
            why = "timer";
            if (!due && cfg.BelowCap && freeCap >= 0 && freeCap <= cfg.Capacity)
                if (st.LastAsk < 0 || now - st.LastAsk >= CapGapMs) { due = true; why = "capacity"; }
            if (!due) { why = "wait"; return null; }
            st.LastAsk = now;
            return "sell";
        }
    }

    // ============================================================================================================ exercise weapons
    public static class HelperExercise
    {
        public const double IdleMs = 2000, EveryMs = 10000;
        public const int Radius = 5;
        /// <summary>The server's exercise weapons (client ids) and their names (server/README.md "Exercise weapons").</summary>
        public static readonly KeyValuePair<int, string>[] Weapons =
        {
            new KeyValuePair<int, string>(27732, "Exercise Sword"), new KeyValuePair<int, string>(27733, "Exercise Fist Weapon"),
            new KeyValuePair<int, string>(27734, "Exercise Club"), new KeyValuePair<int, string>(27735, "Exercise Bow"),
            new KeyValuePair<int, string>(27736, "Exercise Rod"), new KeyValuePair<int, string>(27737, "Exercise Wand"),
            new KeyValuePair<int, string>(27738, "Durable Exercise Sword"), new KeyValuePair<int, string>(27758, "Exercise Shield"),
        };
        /// <summary>The training dummies (client ids).</summary>
        public static readonly int[] Dummies = { 27751, 27752 };

        /// <summary>The weapon to use: the chosen one (or the first of the list when none is chosen) that you carry; 0 when none.</summary>
        public static int PickWeapon(int chosen, Func<int, int> carried)
        {
            foreach (var w in Weapons)
                if ((chosen == 0 || chosen == w.Key) && carried(w.Key) > 0) return w.Key;
            return 0;
        }

        /// <summary>The nearest dummy on your floor with a clear line (the first found wins a tie).</summary>
        public static bool Nearest(Pos from, IList<KeyValuePair<Pos, int>> dummies, Func<Pos, Pos, bool> sightClear, out Pos at, out int id)
        {
            at = default(Pos); id = 0;
            int best = int.MaxValue;
            foreach (var d in dummies)
            {
                if (d.Key.Z != from.Z || (sightClear != null && !sightClear(d.Key, from))) continue;
                int dist = HelperLogic.Distance(from, d.Key);
                if (dist < best) { best = dist; at = d.Key; id = d.Value; }
            }
            return id != 0;
        }

        /// <summary>Whether the tick may use the weapon now: on, in a protection zone, standing still for 2 s.</summary>
        public static bool Due(HelperExerciseCfg cfg, bool pz, double idleMs) => cfg != null && cfg.Enabled && pz && idleMs >= IdleMs;
    }

    // ============================================================================================================ line of sight
    /// <summary>`g_map.isSightClear`: tiles strictly between two positions on the same floor along a straight line; one that blocks projectiles ends the line.</summary>
    public static class SightLine
    {
        /// <summary>The tiles from a to b without the ends (Bresenham; an even split of a diagonal goes by the x axis first).</summary>
        public static List<Pos> Between(Pos a, Pos b)
        {
            var o = new List<Pos>();
            int dx = Math.Abs(b.X - a.X), dy = Math.Abs(b.Y - a.Y);
            int sx = a.X < b.X ? 1 : -1, sy = a.Y < b.Y ? 1 : -1;
            int err = dx - dy, x = a.X, y = a.Y;
            while (!(x == b.X && y == b.Y))
            {
                int e2 = 2 * err;
                if (e2 > -dy) { err -= dy; x += sx; }
                if (e2 < dx) { err += dx; y += sy; }
                if (!(x == b.X && y == b.Y)) o.Add(new Pos(x, y, a.Z));
            }
            return o;
        }

        /// <summary>True when nothing between blocks (blocks(tile) = a thing that blocks missiles). Different floors never see each other.</summary>
        public static bool Clear(Pos a, Pos b, Func<Pos, bool> blocks)
        {
            if (a.Z != b.Z) return false;
            foreach (var p in Between(a, b)) if (blocks(p)) return false;
            return true;
        }

        public static bool Clear(World w, Pos a, Pos b) => Clear(a, b, p =>
        {
            Tile t;
            if (w == null || !w.Tiles.TryGetValue(p, out t)) return false;   // a tile the client does not know does not block
            foreach (var th in t.Things)
                if (!th.IsCreature && th.Item != null && th.Item.Type != null && th.Item.Type.BlockMissile) return true;
            return false;
        });
    }

    // ============================================================================================================ potion gate
    /// <summary>potiongate.lua: may the helper use a potion or rune it cannot count (it sits in a closed backpack)? A count of 0 still allows a probe every 3 s;
    /// the server's answer decides: "Using ..." means it is there (used like a counted one until a probe fails), "Sorry, not possible." or "You cannot use this object."
    /// means nothing to use, and the item waits 30 s. A spell's refusal never counts.</summary>
    public sealed class PotionGate
    {
        public const double ProbeMs = 3000, ReplyMs = 1500, SettleMs = 500, BackoffMs = 30000;
        public static readonly string[] FailTexts = { "sorry, not possible", "you cannot use this object" };

        sealed class Probe
        {
            public double NextProbe, LastProbe = double.NaN, FailAt = double.NaN;
            public int Order;
            public bool Answered = true, Found;
            public bool HasFail => !double.IsNaN(FailAt);
        }

        readonly Dictionary<int, Probe> items = new Dictionary<int, Probe>();
        int seq;

        Probe Get(int id) { Probe p; if (!items.TryGetValue(id, out p)) items[id] = p = new Probe(); return p; }

        static void Settle(Probe s, double now)
        {
            if (s.HasFail && now - s.FailAt >= SettleMs) { s.NextProbe = s.FailAt + BackoffMs; s.FailAt = double.NaN; s.Found = false; }
        }

        /// <summary>May item `id` be used now? count: what the client counts.</summary>
        public bool Allowed(int id, double now, int count)
        {
            if (count > 0) return true;
            var s = Get(id);
            Settle(s, now);
            if (s.HasFail) return false;   // the answer is not settled yet
            if (s.Found) return true;
            return now >= s.NextProbe;
        }

        /// <summary>The use was sent: a use the client could not count is a probe.</summary>
        public void Used(int id, double now, int count)
        {
            var s = Get(id);
            if (count > 0) { s.NextProbe = 0; return; }
            seq++;
            s.LastProbe = now; s.Order = seq; s.Answered = false;
            if (!s.Found) s.NextProbe = now + ProbeMs;
        }

        Probe Answering(double now, bool takeBack)
        {
            Probe best = null;
            foreach (var s in items.Values)
                if (!double.IsNaN(s.LastProbe) && now - s.LastProbe <= ReplyMs && !s.Answered && (best == null || s.Order < best.Order)) best = s;
            if (best != null || !takeBack) return best;
            foreach (var s in items.Values)
                if (!double.IsNaN(s.LastProbe) && now - s.LastProbe <= ReplyMs && s.HasFail && (best == null || s.Order > best.Order)) best = s;
            return best;
        }

        /// <summary>A server text: "Using ..." marks the answered probe found; a failure holds it and it backs off unless its own "Using ..." follows. True when the text answered a probe.</summary>
        public bool OnText(string text, double now)
        {
            string t = (text ?? "").ToLowerInvariant();
            if (t.StartsWith("using ", StringComparison.Ordinal))
            {
                var s = Answering(now, true);
                if (s == null) return false;
                s.Answered = true; s.FailAt = double.NaN; s.Found = true; s.NextProbe = 0;
                return true;
            }
            bool failure = false;
            foreach (string f in FailTexts) if (t.Contains(f)) failure = true;
            if (!failure) return false;
            var p = Answering(now, false);
            if (p == null) return false;
            p.Answered = true; p.FailAt = now;
            return true;
        }

        public void Reset() { items.Clear(); }
    }

    // ============================================================================================================ level-up notice
    public enum LevelUpAction { None, Notice, Apply }

    /// <summary>What a level-up does (autorotation.lua levelUpAction): the helper never changes the player's spells unasked. sel = the rotation for the new level
    /// (topUp false). Apply only with "Auto-update my spells" and a rotation the Auto setup button wrote; a Notice asks "Add to rotation?" for the new ones.</summary>
    public static class RotationLevelUp
    {
        /// <summary>A rotation the player set up: spells that are not none and not the set Auto setup wrote last.</summary>
        public static bool IsCustom(IList<int> ids, IList<int> marker)
        {
            if (ids == null || ids.Count == 0) return false;
            return !(marker != null && Same(ids, marker));
        }

        public static bool Same(IList<int> a, IList<int> b)
        {
            if (a.Count != b.Count) return false;
            for (int i = 0; i < a.Count; i++) if (a[i] != b[i]) return false;
            return true;
        }

        public static LevelUpAction Decide(RotSelection sel, IList<int> currentIds, IList<int> marker, bool autoUpdate, ISet<int> ignored, out List<int> newIds)
        {
            newIds = new List<int>();
            if (sel == null) return LevelUpAction.None;
            var have = new HashSet<int>(currentIds ?? new int[0]);
            foreach (int id in sel.Ids)
                if (!have.Contains(id) && (ignored == null || !ignored.Contains(id))) newIds.Add(id);
            bool custom = IsCustom(currentIds, marker);
            if (autoUpdate && !custom && !Same(currentIds ?? new int[0], sel.Ids) && newIds.Count > 0) return LevelUpAction.Apply;
            return newIds.Count > 0 ? LevelUpAction.Notice : LevelUpAction.None;
        }

        /// <summary>The first `max` spells of a selection: the shooter has five slots, so a longer selection (the ultimate comes first and makes it six) is compared by what fits.</summary>
        public static RotSelection Trim(RotSelection sel, int max)
        {
            if (sel == null || sel.Ids.Count <= max) return sel;
            var t = new RotSelection { Level = sel.Level, Gap = sel.Gap, Changed = sel.Changed, Ultimate = sel.Ultimate };
            for (int i = 0; i < max; i++) { t.Ids.Add(sel.Ids[i]); t.Creatures.Add(i < sel.Creatures.Count ? sel.Creatures[i] : 1); }
            return t;
        }

        /// <summary>"Add": the new spells go into the empty slots, in rotation order, as the creature counts of the selection say; slots in use stay as they are.
        /// Returns how many fitted (the shooter has five slots).</summary>
        public static int AddNew(IList<HelperSlot> slots, RotSelection sel, IList<int> newIds)
        {
            int added = 0;
            foreach (int id in newIds)
            {
                int free = -1;
                for (int i = 0; i < slots.Count; i++) if (slots[i].Id == 0) { free = i; break; }
                if (free < 0) break;
                int at = sel.Ids.IndexOf(id);
                int creatures = at >= 0 && at < sel.Creatures.Count ? sel.Creatures[at] : 1;
                slots[free] = new HelperSlot { Id = id, Percent = 0, Creatures = Math.Max(1, Math.Min(HelperConfig.CreaturesMax, creatures)), Priority = free + 1 };
                added++;
            }
            return added;
        }
    }

    /// <summary>The level-up notice the window shows: the new spell names and what Add and Ignore do.</summary>
    public sealed class LevelUpNotice
    {
        public readonly List<int> NewIds = new List<int>();
        public readonly List<string> Names = new List<string>();
        public RotSelection Selection;
        public string List => string.Join(", ", Names);
        /// <summary>"New spell available: A, B." (the box of autorotation_ui.lua onLevelUp; Unity shows it in the Helper window and as a toast).</summary>
        public string Line => Loc.T("New spell available: {0}.", List);
    }

    // ============================================================================================================ the host and the engine glue
    /// <summary>What the track X helper parts need from the game, beyond IHelperHost and IHelperHostExt. A host without it runs the older parts only.</summary>
    public interface IHelperHostP7
    {
        /// <summary>The creature the character follows now (0: none).</summary>
        uint FollowTarget { get; }
        void Follow(uint id);
        void CancelFollow();
        bool SightClear(Pos a, Pos b);
        /// <summary>Milliseconds since the character last changed tile.</summary>
        double IdleMs { get; }
        /// <summary>Map items of these client ids within `radius` tiles of the character, with their tiles.</summary>
        IList<KeyValuePair<Pos, int>> MapItems(int[] ids, int radius);
        bool UseWithMapItem(int clientId, Pos at, int mapItemId);
        /// <summary>Use by id (the hotkey use): the server finds the item in any carried bag. Creature 0 is yourself.</summary>
        bool UseByIdOnCreature(int clientId, uint creature);
        SellerView Seller { get; }
        void SellerSync();
        void SellerSell();
        /// <summary>Free capacity in oz, -1 when not known.</summary>
        double FreeCapacity { get; }
    }

    public sealed partial class HelperEngine
    {
        public const double EveryFollow = 250, EverySell = 1000, EveryExercise = 10000;

        public readonly FollowState FollowRun = new FollowState();
        public readonly SellState SellRun = new SellState();
        public readonly PotionGate Gate = new PotionGate();
        public string FollowWhy = "off", SellWhy = "off";
        public int FollowAsks, SellAsks, ExerciseUses, GateProbes;
        int lastLevelSeen;
        /// <summary>The level-up notice waiting for Add or Ignore (null: none).</summary>
        public LevelUpNotice LevelNotice;
        /// <summary>The line the last level-up wrote (Auto-update, or Add), for the window to show.</summary>
        public string LevelMessage = "";

        IHelperHostP7 HostP7 => Host as IHelperHostP7;

        /// <summary>The line-of-sight check of the main client (`g_map.isSightClear`) for the area counts, the ally heals and the attack runes; null without a host that has a map.</summary>
        Func<Pos, Pos, bool> Sight { get { var p7 = HostP7; return p7 == null ? null : (Func<Pos, Pos, bool>)p7.SightClear; } }

        void ResetP7()
        {
            FollowRun.LastAsk = -1; FollowRun.HoldUntil = 0; FollowRun.Fails = 0; FollowRun.Ours = false;
            SellRun.LastAsk = -1; SellRun.LastSync = -1; SellRun.Start = -1;
            Gate.Reset();
            LevelNotice = null;
            lastLevelSeen = 0;
            lastVocation = 0; vocationChangedAt = -1;
        }

        /// <summary>Follow, Auto sell and the exercise weapon: one pass of each when due (called by Tick, before the fight systems).</summary>
        void P7Tick(bool pz)
        {
            var p7 = HostP7;
            if (p7 == null) return;
            if (Due("follow", EveryFollow)) FollowTick(p7, pz);
            if (Due("sell", EverySell)) SellTick(p7);
            if (Due("exercise", EveryExercise)) ExerciseTick(p7, pz);
        }

        void FollowTick(IHelperHostP7 p7, bool pz)
        {
            var ext = HostExt;
            var cfg = Config.Follow;
            var players = cfg.Enabled && ext != null ? ext.Players() : null;
            var leader = HelperFollow.LeaderOf(cfg, players);
            string act = HelperFollow.Decide(cfg, FollowRun, new FollowInput { HelperOn = Config.Enabled, Pz = pz, Leader = leader, From = Host.Position, Following = p7.FollowTarget, Now = Host.Now }, out string why);
            FollowWhy = why;
            if (act == "follow" && leader != null) { p7.Follow(leader.Id); FollowAsks++; }
            else if (act == "release") p7.CancelFollow();
        }

        void SellTick(IHelperHostP7 p7)
        {
            string act = HelperSell.Decide(Config.Sell, SellRun, p7.Seller, Host.Now, p7.FreeCapacity, Config.Enabled, out string why);
            SellWhy = why;
            if (act == "sync") p7.SellerSync();
            else if (act == "sell") { p7.SellerSell(); SellAsks++; }
        }

        void ExerciseTick(IHelperHostP7 p7, bool pz)
        {
            var cfg = Config.Exercise;
            if (!HelperExercise.Due(cfg, pz, p7.IdleMs)) return;
            int weapon = HelperExercise.PickWeapon(cfg.Id, Host.ItemCount);
            if (weapon == 0) return;
            var pos = Host.Position;
            if (!HelperExercise.Nearest(pos, p7.MapItems(HelperExercise.Dummies, HelperExercise.Radius), p7.SightClear, out Pos at, out int dummy)) return;
            if (p7.UseWithMapItem(weapon, at, dummy)) ExerciseUses++;
        }

        /// <summary>A server text: the potion gate reads the answer to a probe.</summary>
        public void OnServerText(string text) { Gate.OnText(text, Host.Now); }

        // ---- potions and runes the client cannot count
        /// <summary>Count 0 does not end it: a use by id may find the item in a closed backpack. The gate paces the probes.</summary>
        bool Probeable(int id, int count) => count > 0 || (HostP7 != null && Gate.Allowed(id, Host.Now, count));

        // ---- the level-up notice
        /// <summary>Looks at the level: a rise is a level-up (the first reading of a login is not). With the spell list loaded it decides between nothing, a notice and, with
        /// Auto-update and a rotation Auto setup wrote, an update. Call every pass (cheap).</summary>
        public void LevelWatch(int vocation)
        {
            int level = Host.Level;
            if (level <= 0) return;
            int old = lastLevelSeen;
            lastLevelSeen = level;
            if (old <= 0 || level <= old || !Book.Loaded) return;
            OnLevelUp(vocation);
        }

        // ---- a class change (the store's Vocation Change, an ascension)
        int lastVocation;
        double vocationChangedAt = -1;
        /// <summary>How many spells class changes took out of the helper since it started.</summary>
        public int ClassDrops;

        /// <summary>A vocation that changes from a real one (the first of a login is not a change) takes the old class's spells out of the helper 400 ms later, after the
        /// spell list of the same packet (autorotation_ui.lua onVocationChange, dropOldClass).</summary>
        public void VocationWatch(int vocation)
        {
            if (vocation <= 0) return;
            if (lastVocation > 0 && vocation != lastVocation) vocationChangedAt = Host.Now;
            lastVocation = vocation;
            if (vocationChangedAt >= 0 && Host.Now - vocationChangedAt >= 400 && Book.Loaded)
            {
                vocationChangedAt = -1;
                DropOldClass(vocation);
            }
        }

        /// <summary>Empties the shooter slots and the healing rows of spells the class cannot cast (the server refuses every one of them); a spell the list does not know stays.
        /// Returns how many went. The marker is forgotten: the next Auto setup starts clean.</summary>
        public int DropOldClass(int vocation)
        {
            if (vocation <= 0) return 0;
            Func<int, bool> classOk = id =>
            {
                var sp = Book.ById(id);
                return sp == null || sp.Vocations.Count == 0 || sp.Vocations.Contains(vocation);
            };
            int dropped = 0;
            for (int i = 0; i < Config.Shooter.Count; i++)
                if (Config.Shooter[i].Id != 0 && !classOk(Config.Shooter[i].Id)) { Config.Shooter[i] = new HelperSlot { Priority = i + 1 }; dropped++; }
            for (int i = 0; i < Config.Heals.Count; i++)
                if (Config.Heals[i].Id != 0 && !classOk(Config.Heals[i].Id)) { Config.Heals[i] = new HelperHealRow(); dropped++; }
            if (dropped > 0)
            {
                Config.AutoMarker.Clear();
                LevelNotice = null;
                ClassDrops += dropped;
                LevelMessage = Loc.T("Class changed: {0} spell(s) of your old class were taken out of the Helper. Press Auto setup for your new class.", dropped);
            }
            return dropped;
        }

        public LevelUpAction OnLevelUp(int vocation)
        {
            var sel = RotationLevelUp.Trim(HelperRotation.Select(vocation, Host.Level, CanCast, false), HelperConfig.Slots);
            var ids = new List<int>();
            foreach (var s in Config.Shooter) if (s.Id != 0) ids.Add(s.Id);
            var marker = Config.AutoMarker.Count > HelperConfig.Slots ? Config.AutoMarker.GetRange(0, HelperConfig.Slots) : Config.AutoMarker;   // what fitted the five slots
            var action = RotationLevelUp.Decide(sel, ids, marker, Config.AutoUpdateSpells, Config.IgnoredSpells, out var newIds);
            if (action == LevelUpAction.Apply)
            {
                LevelMessage = AutoSetup(vocation) ?? "";
                LevelNotice = null;
            }
            else if (action == LevelUpAction.Notice)
            {
                var n = new LevelUpNotice { Selection = sel };
                foreach (int id in newIds) { n.NewIds.Add(id); var sp = Book.ById(id); n.Names.Add(sp != null ? sp.Name : "#" + id); }
                LevelNotice = n;
            }
            return action;
        }

        /// <summary>Add: the new spells go into the empty slots. Returns how many fitted (0 when the five slots are in use).</summary>
        public int AcceptLevelNotice()
        {
            var n = LevelNotice;
            LevelNotice = null;
            if (n == null) return 0;
            int added = RotationLevelUp.AddNew(Config.Shooter, n.Selection, n.NewIds);
            // the marker stays only for a rotation the button wrote: a notice that was added by hand makes it the player's
            if (added > 0) Config.AutoMarker.Clear();
            return added;
        }

        /// <summary>Ignore: these spells are not offered again for this character.</summary>
        public void IgnoreLevelNotice()
        {
            var n = LevelNotice;
            LevelNotice = null;
            if (n != null) foreach (int id in n.NewIds) Config.IgnoredSpells.Add(id);
        }
    }

    public static class HelperTextsP7
    {
        /// <summary>The status line of the Follow part (English keys).</summary>
        public static string FollowText(string why)
        {
            switch (why)
            {
                case "following": return "Following";
                case "ask": return "Asking to follow";
                case "away": return "Leader out of view";
                case "pz": return "Paused: protection zone";
                case "helperoff": return "Helper off";
                case "near": return "Close enough";
                case "adjacent": return "Next to the leader";
                case "other": return "Following someone else";
                case "retry": case "giveup": return "Cannot reach the leader";
                case "gap": return "Waiting";
                default: return "Off";
            }
        }

        public static string SellText(string why)
        {
            switch (why)
            {
                case "timer": case "capacity": return "Asked the Auto Seller";
                case "wait": return "Waiting for the timer";
                case "cooldown": return "The Auto Seller is cooling down";
                case "locked": return "The Auto Seller is not unlocked";
                case "unknown": return "Asking the server about the Auto Seller";
                case "helperoff": return "Helper off";
                case "gap": return "Waiting";
                default: return "Off";
            }
        }

        public static string Minutes(int m) => m.ToString(CultureInfo.InvariantCulture);
    }
}
