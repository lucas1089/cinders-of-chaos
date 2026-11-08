// Phase 7, track Z: gaps of the gameplay system rows (docs/UNITY_PARITY.md). Pure logic, no UnityEngine. Tests: Core.Tests/Phase7ZTests.cs.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    // ---------------------------------------------------------------------------------------------------- game_autotarget: reach
    /// <summary>game_autotarget, the reach rule (autotarget.lua reach / search): can the character get to a monster in at most AutoTargetCore.MaxSteps steps, or shoot it
    /// (ranged classes with a clear line). Answers are kept FreshMs and reused; when a tick's path budget is spent an answer up to StaleMs old is still used, else null (not known).
    /// The path and the sight come from hooks: the host runs PathFinder on the known tiles.</summary>
    public sealed class ReachCache
    {
        public double FreshMs = 600, StaleMs = 3000;
        public int PathBudget = 4;
        /// <summary>Steps to the monster (-1: no path). Asked at most PathBudget times per tick.</summary>
        public Func<Pos, Pos, int> Steps;
        /// <summary>A clear line between the two tiles.</summary>
        public Func<Pos, Pos, bool> Sight;

        sealed class Entry { public double T; public int Steps; public bool Sight; }
        readonly Dictionary<uint, Entry> cache = new Dictionary<uint, Entry>();
        double tickAt = -1e9;
        int used;

        /// <summary>One Auto Target tick shares one budget: a new tick starts 50 ms after the last one.</summary>
        public void NewTick(double now)
        {
            if (now - tickAt >= 50) { tickAt = now; used = 0; }
        }

        public int SearchesThisTick => used;
        public void Clear() { cache.Clear(); used = 0; tickAt = -1e9; }

        /// <summary>true: reachable (dist is the steps to walk, or the straight distance when a ranged class has sight), false: not, null: unknown this tick.</summary>
        public bool? Query(uint id, Pos from, Pos to, bool ranged, double now, out double dist)
        {
            dist = 0;
            int straight = AutoTargetCore.Distance(from, to);
            if (straight < 0) return false;
            cache.TryGetValue(id, out var e);
            if (e == null || now - e.T > FreshMs)
            {
                if (used < PathBudget && Steps != null)
                {
                    used++;
                    int steps = Steps(from, to);
                    bool sight = ranged && (straight <= 1 || (Sight != null && Sight(from, to)));
                    e = new Entry { T = now, Steps = steps, Sight = sight };
                    cache[id] = e;
                }
                else if (e == null || now - e.T > StaleMs) return null;
            }
            return AutoTargetCore.Assess(e.Steps, e.Sight, straight, ranged, out dist);
        }
    }


    // ---------------------------------------------------------------------------------------------------- game_craftskills: rows of the Skills window
    /// <summary>One profession row of the Skills window (craftskills.lua paint): short level, green when boosted, the percent bar and the tooltip.</summary>
    public sealed class CraftSkillRow
    {
        public string Name, Value, Tip;
        public int Percent;
        public bool Boosted;
    }

    public static class CraftSkillRows
    {
        public static List<CraftSkillRow> Build(IList<SkillValue> values)
        {
            var o = new List<CraftSkillRow>();
            if (values == null) return o;
            for (int i = 0; i < CraftTableState.SkillNames.Length && i < values.Count; i++)
            {
                var v = values[i];
                o.Add(new CraftSkillRow { Name = Loc.T(CraftTableState.SkillNames[i]), Value = CraftSkills.ShortLevel(v.Level), Tip = CraftSkills.Tooltip(i, v), Percent = v.Percent, Boosted = v.Level > v.Base });
            }
            return o;
        }

        /// <summary>The main client builds the block when the first value arrives: nothing is drawn until the packet has sent a skill (any value above 0).</summary>
        public static bool Any(IList<SkillValue> values)
        {
            if (values == null) return false;
            foreach (var v in values) if (v.Level > 0 || v.Base > 0 || v.Percent > 0) return true;
            return false;
        }
    }
}
