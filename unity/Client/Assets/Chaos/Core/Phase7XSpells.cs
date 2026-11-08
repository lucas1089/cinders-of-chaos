// Phase 7 track X, spellbook: the area preview and the detail rows of game_spellbook (spellbook.lua areaRoles, areaNote, vocationText,
// the stat rows of showDetails). Pure rules, tested in Core.Tests/Phase7XTests.cs.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public enum AreaRole { Empty, Hit, Caster, Target, TargetHit }

    public static class SpellArea
    {
        /// <summary>A single-target preview puts the target at most this many tiles from you (spellbook.lua MAX_SINGLE_RANGE).</summary>
        public const int MaxSingleRange = 5;
        public const int MaxCell = 14, MinCell = 5;

        /// <summary>The grid of the area: rows of roles. An area or front spell draws its matrix (1 hit; 2 and 3 the centre, which is you or, for a spell
        /// centred on the target, the target, hit with 3); a single-target spell the target at its range with you below; anything else only you.</summary>
        public static AreaRole[][] Roles(Spell sp)
        {
            if (sp == null) return new[] { new[] { AreaRole.Caster } };
            if (sp.Area.Count > 0 && (sp.Target == "area" || sp.Target == "front"))
            {
                var roles = new AreaRole[sp.Area.Count][];
                for (int r = 0; r < roles.Length; r++)
                {
                    var row = sp.Area[r];
                    roles[r] = new AreaRole[row.Count];
                    for (int c = 0; c < row.Count; c++)
                    {
                        int v = row[c];
                        AreaRole role = AreaRole.Empty;
                        if (v == 1) role = AreaRole.Hit;
                        else if (v == 2 || v == 3)
                            role = sp.Center == "target" ? (v == 3 ? AreaRole.TargetHit : AreaRole.Target) : AreaRole.Caster;
                        roles[r][c] = role;
                    }
                }
                return roles;
            }
            if (sp.Target == "single")
            {
                int range = Math.Max(1, Math.Min(MaxSingleRange, sp.Range));
                var rows = new List<AreaRole[]> { new[] { AreaRole.TargetHit } };
                for (int i = 2; i <= range; i++) rows.Add(new[] { AreaRole.Empty });
                rows.Add(new[] { AreaRole.Caster });
                return rows.ToArray();
            }
            return new[] { new[] { AreaRole.Caster } };
        }

        public static int Columns(AreaRole[][] roles)
        {
            int n = 0;
            foreach (var row in roles) n = Math.Max(n, row.Length);
            return n;
        }

        /// <summary>The size of one cell that fits the box: the smaller of the two fits, kept between 5 and 14 pixels.</summary>
        public static int CellSize(AreaRole[][] roles, float boxW, float boxH)
        {
            int cols = Math.Max(1, Columns(roles)), rows = Math.Max(1, roles.Length);
            int cell = (int)Math.Floor(Math.Min((boxW - 8f) / cols, (boxH - 8f) / rows));
            return Math.Max(MinCell, Math.Min(MaxCell, cell));
        }

        /// <summary>Whether the drawn target square is filled with the hit colour (a target that is hit).</summary>
        public static bool HasTargetHit(AreaRole[][] roles)
        {
            foreach (var row in roles) foreach (var r in row) if (r == AreaRole.TargetHit) return true;
            return false;
        }

        /// <summary>The line under the grid (an English key with its argument, or no argument).</summary>
        public static string Note(Spell sp, out int arg)
        {
            arg = 0;
            if (sp == null) return "Affects only you.";
            if (sp.Target == "front") return "Cast facing north (up).";
            if (sp.Target == "area" && sp.Center == "target") return "Centred on the target.";
            if (sp.Target == "area") return "Centred on you.";
            if (sp.Target == "single")
            {
                if (sp.Range > 0) { arg = sp.Range; return "One target, range {0}."; }
                return "One target.";
            }
            return "Affects only you.";
        }

        /// <summary>Tiles an area hits (cells of 1 or 3).</summary>
        public static int HitCells(Spell sp)
        {
            int n = 0;
            foreach (var row in sp.Area) foreach (int v in row) if (v == 1 || v == 3) n++;
            return n;
        }
    }

    /// <summary>The detail rows under a spell (stat key and value as English keys or finished text; Kind says if the value needs a translation).</summary>
    public struct SpellStat
    {
        public string Key, Value;
        /// <summary>The value is an English text for Loc.T (Everyone, Area ...) rather than data.</summary>
        public bool Translate;
        public string Tip;
    }

    public static class SpellDetails
    {
        public static string Capitalize(string s) => string.IsNullOrEmpty(s) ? "" : char.ToUpperInvariant(s[0]) + s.Substring(1);

        /// <summary>"4s", "2.5s", "-" for none.</summary>
        public static string Seconds(int ms)
        {
            if (ms <= 0) return "-";
            double s = ms / 1000.0;
            return s == Math.Floor(s) ? ((int)s).ToString(CultureInfo.InvariantCulture) + "s" : s.ToString("0.0", CultureInfo.InvariantCulture) + "s";
        }

        /// <summary>"Master Sorcerer" gives "MS"; a one word name keeps three letters ("Berserker" gives "Ber").</summary>
        public static string Initials(string name)
        {
            var words = new List<string>();
            var cur = new System.Text.StringBuilder();
            foreach (char c in name ?? "")
            {
                if (char.IsLetter(c)) cur.Append(c);
                else if (cur.Length > 0) { words.Add(cur.ToString()); cur.Clear(); }
            }
            if (cur.Length > 0) words.Add(cur.ToString());
            if (words.Count == 1)
            {
                string w = words[0];
                return char.ToUpperInvariant(w[0]) + (w.Length > 1 ? w.Substring(1, Math.Min(2, w.Length - 1)).ToLowerInvariant() : "");
            }
            var sb = new System.Text.StringBuilder();
            foreach (string w in words) sb.Append(char.ToUpperInvariant(w[0]));
            return sb.ToString();
        }

        public const int VocationInitialsMax = 3;

        /// <summary>The Vocations row: "Everyone" for none listed, up to three initials, else "Every class" (no named class is missing) or "N classes"; the names go in the tip.</summary>
        public static SpellStat Vocations(Spell sp, IDictionary<int, string> names)
        {
            var ids = new List<int>(sp.Vocations);
            if (ids.Count == 0) return new SpellStat { Key = "Vocations", Value = "Everyone", Translate = true };
            ids.Sort();
            var shortList = new List<string>();
            var full = new List<string>();
            var has = new HashSet<int>(ids);
            foreach (int id in ids)
            {
                string n = names != null && names.TryGetValue(id, out var nn) ? nn : "#" + id.ToString(CultureInfo.InvariantCulture);
                shortList.Add(Initials(n));
                full.Add(n);
            }
            string tip = string.Join(", ", full);
            if (shortList.Count > VocationInitialsMax)
            {
                bool missing = false, named = false;
                if (names != null)
                    foreach (var kv in names)
                        if (kv.Key > 0) { named = true; if (!has.Contains(kv.Key)) { missing = true; break; } }
                if (named && !missing) return new SpellStat { Key = "Vocations", Value = "Every class", Translate = true, Tip = tip };
                return new SpellStat { Key = "Vocations", Value = shortList.Count.ToString(CultureInfo.InvariantCulture) + " classes", Translate = false, Tip = tip };
            }
            return new SpellStat { Key = "Vocations", Value = string.Join(", ", shortList), Tip = tip };
        }

        /// <summary>The rows after Level, Magic level, Mana and Cooldown that the main client shows: Soul, Group, Type, Element, Target, Scales, Vocations.</summary>
        public static List<SpellStat> Rows(Spell sp, IDictionary<int, string> vocationNames)
        {
            var rows = new List<SpellStat>();
            if (sp.Soul > 0) rows.Add(new SpellStat { Key = "Soul", Value = sp.Soul.ToString(CultureInfo.InvariantCulture) });
            string group = sp.Group == 1 ? "Attack" : sp.Group == 2 ? "Healing" : sp.Group == 3 ? "Support" : sp.Group == 4 ? "Special" : "-";
            rows.Add(new SpellStat { Key = "Group", Value = group, Translate = group != "-" });
            string type;
            switch (sp.Type)
            {
                case "damage": type = "Damage"; break;
                case "heal": type = "Healing"; break;
                case "buff": type = "Support"; break;
                case "summon": type = "Summon"; break;
                case "conjure": type = "Conjure"; break;
                case "utility": type = "Utility"; break;
                default: type = sp.Type.Length > 0 ? Capitalize(sp.Type) : "-"; break;
            }
            rows.Add(new SpellStat { Key = "Type", Value = type, Translate = type != "-" && sp.Type.Length > 0 && (sp.Type == "damage" || sp.Type == "heal" || sp.Type == "buff" || sp.Type == "summon" || sp.Type == "conjure" || sp.Type == "utility") });
            rows.Add(new SpellStat { Key = "Element", Value = sp.Element.Length > 0 ? Capitalize(sp.Element) : "-" });
            string target = sp.Target == "single" ? "Single target" : sp.Target == "area" ? "Area" : sp.Target == "self" ? "Self" : sp.Target == "front" ? "Area in front" : "-";
            rows.Add(new SpellStat { Key = "Target", Value = target, Translate = target != "-" });
            if (sp.Scaling.Length > 0)
            {
                string shortScale = sp.Scaling.Replace("distance skill x weapon attack", "dist. x weapon").Replace("skill x weapon attack", "skill x weapon");
                rows.Add(new SpellStat { Key = "Scales", Value = shortScale, Tip = sp.Scaling });
            }
            rows.Add(Vocations(sp, vocationNames));
            return rows;
        }
    }
}
