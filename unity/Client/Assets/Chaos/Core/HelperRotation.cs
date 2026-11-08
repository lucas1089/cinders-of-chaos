// The helper's "Auto setup": which attack spells go into the five rotation slots and which heals into the healing rows, from the
// character's class, level and the spells it can cast. A port of game_helperrotation/autorotation.lua (the selection logic); the data
// (HelperRotationData.cs) is generated from autorotation_data.lua by unity/tools/gen_helper_rotation_data.lua.
// A spell the character cannot cast is replaced by the next one of an earlier preset, an area spell goes before a single-target one,
// and the class's ultimate (level 1200) comes first and takes no slot of the five.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class RotPreset
    {
        public readonly int Level;
        public readonly double Gap;
        public readonly int[] Spells, Creatures;
        public RotPreset(int level, double gap, int[] spells, int[] creatures) { Level = level; Gap = gap; Spells = spells; Creatures = creatures; }
    }

    public sealed class RotHeal { public readonly int Id, Level; public RotHeal(int id, int level) { Id = id; Level = level; } }

    public sealed class RotClass
    {
        public int Id, Ultimate;
        public string Name = "";
        public readonly List<RotPreset> Presets = new List<RotPreset>();
        public readonly List<int> Extras = new List<int>();
        public readonly List<RotHeal> Heals = new List<RotHeal>();
    }

    public sealed class RotSpell
    {
        public int Id, Cooldown, GroupCooldown, SecondaryCooldown, Cast;
        public string Name = "", Words = "", SecondaryGroup = "";
        public bool Area, Chi;
    }

    public static partial class HelperRotationData
    {
        public static double Gcd;
    }

    /// <summary>The result of Select: the spell ids in cast order with their creature counts, the longest wait between two casts in seconds.</summary>
    public sealed class RotSelection
    {
        public int Level;
        public readonly List<int> Ids = new List<int>();
        public readonly List<int> Creatures = new List<int>();
        public double Gap;
        public bool Changed;
        public int Ultimate;
    }

    public static class HelperRotation
    {
        public const int MaxSpells = 5;          // attack spells in a rotation, the ultimate not counted
        public const double Horizon = 120;       // seconds the gap check simulates
        public static readonly int[] HealPercents = { 45, 65, 85 };   // the healing rows: the strongest heal at the lowest health

        static Dictionary<int, RotClass> classes;
        static Dictionary<int, RotSpell> spells;

        static void Load()
        {
            if (classes != null) return;
            var c = new Dictionary<int, RotClass>();
            var s = new Dictionary<int, RotSpell>();
            HelperRotationData.Fill(c, s);
            classes = c; spells = s;
        }

        public static IDictionary<int, RotClass> Classes { get { Load(); return classes; } }
        public static IDictionary<int, RotSpell> SpellData { get { Load(); return spells; } }

        public static RotClass ClassOf(int vocation) { Load(); RotClass c; return classes.TryGetValue(vocation, out c) ? c : null; }

        /// <summary>The preset of the highest level at or below `level`, and its index (-1: none).</summary>
        public static RotPreset PresetFor(int vocation, int level, out int index)
        {
            index = -1;
            var c = ClassOf(vocation);
            if (c == null) return null;
            RotPreset best = null;
            for (int i = 0; i < c.Presets.Count; i++) if (c.Presets[i].Level <= level) { best = c.Presets[i]; index = i; }
            return best;
        }

        /// <summary>The longest time between two casts of a priority rotation (ids in priority order), in seconds: the spell cooldowns, the cast
        /// spell's group cooldown on the attack group, secondary groups and cast times, from a fresh start.</summary>
        public static double Gap(IList<int> ids)
        {
            Load();
            var list = new List<RotSpell>();
            foreach (int id in ids) { RotSpell s; if (spells.TryGetValue(id, out s)) list.Add(s); }
            if (list.Count == 0) return Horizon;
            var ready = new double[list.Count];
            double attackGroup = 0;
            var group = new Dictionary<string, double>();
            double t = 0, last = -1, gap = 0;
            while (t < Horizon)
            {
                int pick = -1;
                double soonest = -1;
                for (int i = 0; i < list.Count; i++)
                {
                    var s = list[i];
                    double sec = 0;
                    if (s.SecondaryGroup != "") group.TryGetValue(s.SecondaryGroup, out sec);
                    double at = Math.Max(ready[i], Math.Max(attackGroup, sec));
                    if (at <= t + 1e-9) { pick = i; break; }
                    soonest = soonest < 0 ? at : Math.Min(soonest, at);
                }
                if (pick < 0) { t = soonest >= 0 ? soonest : Horizon; continue; }
                var sp = list[pick];
                if (last >= 0 && t - last > gap) gap = t - last;
                last = t;
                ready[pick] = t + sp.Cooldown / 1000.0;
                double hold = Math.Max(sp.GroupCooldown, sp.Cast) / 1000.0;
                attackGroup = t + hold;
                if (sp.SecondaryGroup != "") group[sp.SecondaryGroup] = t + sp.SecondaryCooldown / 1000.0;
                t += Math.Max(hold, 0.001);
            }
            return Math.Floor(gap * 100 + 0.5) / 100;
        }

        /// <summary>The ids with the area spells first, then the others, each group in its order (the creature counts follow their spell).
        /// Returns whether the order changed.</summary>
        public static bool AreaFirst(List<int> ids, List<int> creatures)
        {
            Load();
            var outIds = new List<int>(); var outCr = new List<int>(); var rest = new List<int>(); var restCr = new List<int>();
            for (int i = 0; i < ids.Count; i++)
            {
                RotSpell s;
                if (spells.TryGetValue(ids[i], out s) && s.Area) { outIds.Add(ids[i]); outCr.Add(creatures[i]); }
                else { rest.Add(ids[i]); restCr.Add(creatures[i]); }
            }
            outIds.AddRange(rest); outCr.AddRange(restCr);
            bool moved = false;
            for (int i = 0; i < ids.Count; i++) if (ids[i] != outIds[i]) { moved = true; break; }
            ids.Clear(); ids.AddRange(outIds);
            creatures.Clear(); creatures.AddRange(outCr);
            return moved;
        }

        /// <summary>The rotation for a character. canCast(id): the character can cast the spell (knows it, its class and level). topUp false: the
        /// preset alone (the level-up check only looks for new spells). Returns null when the class is unknown, no preset fits the level or the
        /// character can cast none of the spells.</summary>
        public static RotSelection Select(int vocation, int level, Func<int, bool> canCast, bool topUp = true)
        {
            Load();
            var c = ClassOf(vocation);
            if (c == null) return null;
            int index;
            var preset = PresetFor(vocation, level, out index);
            if (preset == null) return null;
            if (canCast == null) canCast = id => true;
            var ids = new List<int>(); var creatures = new List<int>(); var seen = new HashSet<int>();
            bool changed = false, added = false;
            for (int i = 0; i < preset.Spells.Length; i++)
            {
                int id = preset.Spells[i];
                if (canCast(id)) { ids.Add(id); creatures.Add(i < preset.Creatures.Length ? preset.Creatures[i] : 1); seen.Add(id); }
                else changed = true;
            }
            // top it up to MaxSpells with the other spells the character can cast: earlier presets newest first, then the later ones
            if (topUp)
            {
                var order = new List<int>();
                for (int j = index - 1; j >= 0; j--) order.Add(j);
                for (int j = index + 1; j < c.Presets.Count; j++) order.Add(j);
                foreach (int j in order)
                {
                    if (ids.Count >= MaxSpells) break;
                    foreach (int id in c.Presets[j].Spells)
                        if (ids.Count < MaxSpells && !seen.Contains(id) && canCast(id)) { ids.Add(id); creatures.Add(1); seen.Add(id); added = true; }
                }
                // the class's attack spells no preset holds (newest first) come last
                foreach (int id in c.Extras)
                {
                    if (ids.Count >= MaxSpells) break;
                    if (!seen.Contains(id) && canCast(id)) { ids.Add(id); creatures.Add(1); seen.Add(id); added = true; }
                }
            }
            int ultimate = c.Ultimate;
            if (ultimate > 0 && canCast(ultimate) && !seen.Contains(ultimate)) seen.Add(ultimate); else ultimate = 0;
            if (ids.Count == 0) return null;
            bool moved = AreaFirst(ids, creatures);
            double gap = (changed || added || moved) ? Gap(ids) : preset.Gap;
            if (ultimate > 0) { ids.Insert(0, ultimate); creatures.Insert(0, 1); }   // one creature is enough: a lone boss gets the ultimate too
            var sel = new RotSelection { Level = preset.Level, Gap = gap, Changed = changed, Ultimate = ultimate };
            sel.Ids.AddRange(ids); sel.Creatures.AddRange(creatures);
            return sel;
        }

        /// <summary>The healing rows for the class: up to 3 heals it can cast, the strongest (highest level) at the lowest health.</summary>
        public static List<HelperHealRow> Heals(int vocation, int level, Func<int, bool> canCast = null)
        {
            var o = new List<HelperHealRow>();
            var c = ClassOf(vocation);
            if (c == null) return o;
            foreach (var h in c.Heals)
                if (o.Count < HealPercents.Length && h.Level <= level && (canCast == null || canCast(h.Id))) o.Add(new HelperHealRow { Id = h.Id, Percent = HealPercents[o.Count] });
            return o;
        }

        /// <summary>The rows of a selection as shooter slots, cast order = priority order.</summary>
        public static List<HelperSlot> Slots(RotSelection sel)
        {
            var o = new List<HelperSlot>();
            for (int i = 0; i < sel.Ids.Count && i < HelperConfig.Slots; i++)
                o.Add(new HelperSlot { Id = sel.Ids[i], Percent = 0, Creatures = Math.Max(1, Math.Min(HelperConfig.CreaturesMax, sel.Creatures[i])), Priority = i + 1 });
            return o;
        }

        public static string Message(RotSelection sel, Func<int, string> nameOf)
        {
            var names = new List<string>();
            foreach (int id in sel.Ids) names.Add(nameOf != null ? nameOf(id) : id.ToString());
            return Loc.T("Rotation set: {0} (max gap {1} s)", string.Join(" > ", names), sel.Gap.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture));
        }
    }
}
