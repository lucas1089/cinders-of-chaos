// Ports of the small guard modules of the main client (O433 phase 5, track P): game_deadguard (a dead monster that stays drawn), game_targetguard
// (the own summons are never a locked target), game_autotarget (class order and reach of the helper's Auto Target), game_lootscreen (loot lines stay off the
// game screen) and game_badgeslot (slot 13). The pure rules of the Lua modules, with the same numbers; the engine glue is in GamePlay.cs and HelperEngine.cs.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    // ---------------------------------------------------------------------------------------------------- dead guard
    /// <summary>game_deadguard: a monster whose removal packet was lost stays on the map at 0 percent. 3 seconds at 0 percent in a row (seen by a sweep every
    /// second) and it is taken off locally. Players and the own character are never touched. The Lua module's duplicate and stale checks work on engine
    /// objects of one creature id; the world here keeps one creature per id, so they have nothing to find.</summary>
    public sealed class DeadGuard
    {
        public const double GraceMs = 3000, SweepMs = 1000;

        public struct Seen
        {
            public uint Id;
            public bool IsPlayer, IsSelf, OnMap;
            public int Health;
        }

        readonly Dictionary<uint, double> zeroSince = new Dictionary<uint, double>();

        /// <summary>"skip", "wait" or "remove" for one creature seen at 0 percent for ageMs (deadguard_logic.lua decide).</summary>
        public static string Decide(Seen s, double ageMs)
        {
            if (s.IsPlayer || s.IsSelf || !s.OnMap || s.Health > 0) return "skip";
            return ageMs < GraceMs ? "wait" : "remove";
        }

        /// <summary>The ids to remove now, from everything on the map.</summary>
        public List<uint> Sweep(IEnumerable<Seen> list, double now)
        {
            var o = new List<uint>();
            var seen = new HashSet<uint>();
            foreach (var s in list)
            {
                if (s.IsPlayer || s.IsSelf || !s.OnMap || s.Health > 0) continue;
                seen.Add(s.Id);
                if (!zeroSince.TryGetValue(s.Id, out double since)) { zeroSince[s.Id] = now; since = now; }
                if (Decide(s, now - since) == "remove") o.Add(s.Id);
            }
            var forget = new List<uint>();
            foreach (var id in zeroSince.Keys) if (!seen.Contains(id)) forget.Add(id);
            foreach (var id in forget) zeroSince.Remove(id);
            foreach (var id in o) zeroSince.Remove(id);
            return o;
        }

        public void Reset() { zeroSince.Clear(); }
    }

    // ---------------------------------------------------------------------------------------------------- target guard
    public enum LockAction { Keep, Attack, Drop }

    /// <summary>game_targetguard: the helper's locked target. A lock on the own summon is dropped at once (the server refuses the attack); a lock the server keeps
    /// cancelling (a party member's summon, a protection zone) is dropped after MaxSends re-sends within WindowMs instead of one refused attack per tick.</summary>
    public static class TargetGuard
    {
        public const byte SummonOwn = 3, SummonOther = 4;
        public const int MaxSends = 3;
        public const double WindowMs = 3000;

        public static bool IsOwnSummon(byte type) => type == SummonOwn;
        public static bool IsSummon(byte type) => type == SummonOwn || type == SummonOther;
        public static bool KeepLock(Creature c) => c != null && !IsOwnSummon(c.Type);

        /// <summary>The creatures attack next and previous may pick: every one but the own summons.</summary>
        public static List<Creature> AttackCycle(IEnumerable<Creature> list)
        {
            var o = new List<Creature>();
            foreach (var c in list) if (!IsOwnSummon(c.Type)) o.Add(c);
            return o;
        }
    }

    /// <summary>The re-sends of the current lock (targetguard.lua lockAction).</summary>
    public sealed class TargetLock
    {
        uint id;
        List<double> sends = new List<double>();

        public LockAction Action(uint lockId, uint attackingId, double now)
        {
            if (lockId == 0 || attackingId == lockId) return LockAction.Keep;
            if (id != lockId) { id = lockId; sends = new List<double>(); }
            var kept = new List<double>();
            foreach (double t in sends) if (now - t < TargetGuard.WindowMs) kept.Add(t);
            sends = kept;
            if (kept.Count >= TargetGuard.MaxSends) { id = 0; sends = new List<double>(); return LockAction.Drop; }
            kept.Add(now);
            return LockAction.Attack;
        }

        public void Reset() { id = 0; sends = new List<double>(); }
    }

    // ---------------------------------------------------------------------------------------------------- auto target
    /// <summary>One monster the Auto Target may pick. Rank: 1 loot goblin, 2 boss, 3 special, 4 normal. Reachable null: not known this tick.</summary>
    public sealed class AutoCand
    {
        public uint Id;
        public double Dist = 99;
        public int Health = 100;
        public int Rank = AutoTargetCore.RankNormal;
        public bool? Reachable;
    }

    /// <summary>game_autotarget: which monster the helper's Auto Target picks. Priority: a loot goblin, then a boss, then a special monster (magic, rare, legendary)
    /// before every normal one; within a class the nearest, equal distance the lowest health, then the lowest id. The current target stays while it is valid
    /// unless a better class is reachable. The reach test is a hook (the Lua engine asks the map's pathfinder; the Unity world has none, so a host without a
    /// reach function skips that rule). Rules: autotarget_core.lua.</summary>
    public static class AutoTargetCore
    {
        public const int RankGoblin = 1, RankBoss = 2, RankSpecial = 3, RankNormal = 4;
        public const int MaxSteps = 16;
        public static readonly HashSet<string> Goblins = new HashSet<string> { "treasure goblin", "gem goblin", "shard goblin" };
        public static readonly HashSet<string> SpecialTiers = new HashSet<string> { "magic", "rare", "legendary" };
        public static readonly HashSet<string> BossRoles = new HashSet<string> { "guardian", "omen" };
        /// <summary>Vocation ids of the lines that shoot (docs/CLASSES.md): Ranger, Deadeye, Beastmaster, Mystic, Elementalist, Illusionist, Necromancer, Lich, Bone Lord.</summary>
        public static readonly HashSet<int> RangedVocations = new HashSet<int> { 3, 7, 15, 1, 5, 10, 20, 21, 22 };

        /// <summary>The name without the level suffix ("Gem Goblin [25]"), lower case.</summary>
        public static string BaseName(string name)
        {
            if (name == null) return "";
            int i = name.LastIndexOf('[');
            if (i > 0 && name.EndsWith("]", StringComparison.Ordinal))
            {
                bool digits = i + 2 < name.Length;
                for (int k = i + 1; k < name.Length - 1; k++) if (!char.IsDigit(name[k])) digits = false;
                if (digits) name = name.Substring(0, i);
            }
            return name.Trim().ToLowerInvariant();
        }

        public static bool IsLootGoblin(string name) => Goblins.Contains(BaseName(name));
        public static bool IsRanged(int vocation) => RangedVocations.Contains(vocation);

        public static int ClassOf(string name, string tier, string role)
        {
            if (IsLootGoblin(name)) return RankGoblin;
            if (tier == "boss" || (role != null && BossRoles.Contains(role))) return RankBoss;
            if (tier != null && SpecialTiers.Contains(tier)) return RankSpecial;
            return RankNormal;
        }

        /// <summary>The straight distance (the larger axis), -1 on another floor.</summary>
        public static int Distance(Pos a, Pos b) => a.Z != b.Z ? -1 : Math.Max(Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));

        /// <summary>Can the character get to the monster, and how far. steps: the path length (-1: no path); sight: a clear line (ranged classes shoot over water).</summary>
        public static bool Assess(int steps, bool sight, int straight, bool ranged, out double dist)
        {
            if (ranged && sight) { dist = straight; return true; }
            if (steps >= 0 && steps <= MaxSteps) { dist = steps; return true; }
            dist = 0;
            return false;
        }

        static bool Before(AutoCand a, AutoCand b, bool priority)
        {
            if (priority && a.Rank != b.Rank) return a.Rank < b.Rank;
            if (a.Dist != b.Dist) return a.Dist < b.Dist;
            if (a.Health != b.Health) return a.Health < b.Health;
            return a.Id < b.Id;
        }

        public static List<AutoCand> Sorted(IEnumerable<AutoCand> cands, bool priority)
        {
            var l = new List<AutoCand>(cands);
            l.Sort((a, b) => Before(a, b, priority) ? -1 : Before(b, a, priority) ? 1 : 0);
            return l;
        }

        /// <summary>The best candidate of a priority class that is reachable (reach null: all are), or null.</summary>
        public static AutoCand PickPriority(IEnumerable<AutoCand> cands, Func<AutoCand, bool?> reach)
        {
            foreach (var c in Sorted(cands, true))
            {
                if (c.Rank >= RankNormal) return null;
                if (reach == null || reach(c) == true) return c;
            }
            return null;
        }

        /// <summary>The whole choice: the best reachable candidate, or the current one when it is valid and not worse by class. keep says which.</summary>
        public static AutoCand Choose(IList<AutoCand> cands, bool priority, Func<AutoCand, bool?> reach, uint current, out bool keep)
        {
            keep = false;
            bool? Ok(AutoCand c) => reach == null ? true : reach(c);
            AutoCand best = null;
            foreach (var c in Sorted(cands, priority)) if (Ok(c) == true) { best = c; break; }
            AutoCand cur = null;
            if (current != 0) foreach (var c in cands) if (c.Id == current) { cur = c; break; }
            if (cur != null && Ok(cur) != false && (best == null || !priority || cur.Rank <= best.Rank)) { keep = true; return cur; }
            return best;
        }

        /// <summary>May the locked target stay: false when it cannot be reached any more or a monster of a better class can.</summary>
        public static bool KeepLock(AutoCand locked, IEnumerable<AutoCand> cands, Func<AutoCand, bool?> reach, bool priority)
        {
            if (reach != null && reach(locked) == false) return false;
            if (priority)
            {
                var better = PickPriority(cands, reach);
                if (better != null && better.Rank < locked.Rank) return false;
            }
            return true;
        }
    }

    // ---------------------------------------------------------------------------------------------------- loot screen, badge slot
    /// <summary>game_lootscreen: the loot line ("Loot of a Bone Warrior: 84 gold coins.") stays off the game screen. It still reaches the Server Log and the Loot
    /// channel. Unity draws no status line over the map; any line a future screen message shows asks OnScreen first.</summary>
    public static class LootScreen
    {
        public const byte LootKind = 31;   // MESSAGE_LOOT
        public static bool OnScreen(byte kind) => kind != LootKind;
    }

    /// <summary>game_badgeslot: slot 13 of the equipment holds a badge (server src-patch 0058: the second ring slot is gone). The slot is drawn where the ammunition
    /// slot was; the equipment array has room for it (slots 1 to 13).</summary>
    public static class BadgeSlot
    {
        public const int Slot = 13, InventorySize = 14;
        public const string Tooltip = "Badge";

        /// <summary>The tooltip of an equipment slot: "Badge" on the empty badge slot, "" when an item is in it (the item tooltip takes over), null elsewhere.</summary>
        public static string SlotTooltip(int slot, bool hasItem) => slot != Slot ? null : hasItem ? "" : Loc.T(Tooltip);
    }
}
