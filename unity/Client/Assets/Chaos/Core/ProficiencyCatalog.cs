// The weapon list of the proficiency window (O433 phase 5, track Q). The base window lists the weapons the server's catalogue packet names; the Chaos server
// sends none, so the main client builds the same list from its own item data: every item whose market category is a weapon one and that has a name
// (game_proficiencycatalog/catalogcore.lua). Unity does the same from the dat: the market category and the market name of each item type. The main client also
// accepts a weapon type for an item without market data; the Unity dat has no weapon type (it comes from the item table of the main client), so that
// fallback is a callback (ProficiencyCatalog.Collect) a caller may fill. Unity shows the list as a read-only catalogue (ProficiencyWindow): the perk trees
// of the main client's proficiencies.json are not ported, and there is no experience to show.
// Tests: Core.Tests/InfoTests.cs (mirrors catalogcore_test.lua).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class ProficiencyInfo
    {
        /// <summary>The market category, -1 none.</summary>
        public int Category = -1;
        /// <summary>The weapon category derived from a weapon type when the item has no market data, -1 none.</summary>
        public int TypeCategory = -1;
        public string Name = "";
    }

    public sealed class ProficiencyWeapon { public int Id, Category; public string Name = ""; }

    public static class ProficiencyCatalog
    {
        public const int Axes = 17, Clubs = 18, DistanceWeapons = 19, Swords = 20, WandsRods = 21, FistWeapons = 27;
        public static readonly int[] Categories = { Swords, Axes, Clubs, DistanceWeapons, WandsRods, FistWeapons };

        public static string CategoryName(int c)
        {
            switch (c)
            {
                case Axes: return "Axes";
                case Clubs: return "Clubs";
                case DistanceWeapons: return "Distance Weapons";
                case Swords: return "Swords";
                case WandsRods: return "Wands and Rods";
                case FistWeapons: return "Fist Weapons";
                default: return "Other";
            }
        }

        public static bool IsWeaponCategory(int c) => Array.IndexOf(Categories, c) >= 0;

        /// <summary>The weapons in id order: items whose market category is a weapon one (or whose weapon type maps to one) and that have a name. read gives null for no such item.</summary>
        public static List<ProficiencyWeapon> Collect(Func<int, ProficiencyInfo> read, int firstId, int lastId, out int seen)
        {
            var o = new List<ProficiencyWeapon>();
            seen = 0;
            for (int id = firstId; id <= lastId; id++)
            {
                var info = read(id);
                if (info == null) continue;
                seen++;
                int category = IsWeaponCategory(info.Category) ? info.Category : info.TypeCategory;
                string name = info.Name ?? "";
                if (IsWeaponCategory(category) && name.Length > 0) o.Add(new ProficiencyWeapon { Id = id, Category = category, Name = name });
            }
            return o;
        }

        /// <summary>The weapons of a dat (item types 100 and up).</summary>
        public static List<ProficiencyWeapon> FromDat(DatFile dat, out int seen)
        {
            int last = dat.Items.Length - 1;
            return Collect(id => { var t = dat.Item(id); return t == null ? null : new ProficiencyInfo { Category = t.MarketCategory, Name = t.MarketName }; }, 100, last, out seen);
        }

        /// <summary>The list of one category, by name; category -1: all, and a search text (every word in the name).</summary>
        public static List<ProficiencyWeapon> Filter(IList<ProficiencyWeapon> all, int category, string query)
        {
            var words = new List<string>((query ?? "").ToLowerInvariant().Split((char[])null, StringSplitOptions.RemoveEmptyEntries));
            var o = new List<ProficiencyWeapon>();
            foreach (var w in all)
            {
                if (category >= 0 && w.Category != category) continue;
                string n = w.Name.ToLowerInvariant();
                bool ok = true;
                foreach (var word in words) if (n.IndexOf(word, StringComparison.Ordinal) < 0) { ok = false; break; }
                if (ok) o.Add(w);
            }
            o.Sort((a, b) => string.CompareOrdinal(a.Name, b.Name));
            return o;
        }
    }
}
