// The Ctrl compare view of the item tooltip: what a wearable item adds or takes against the items worn in the slots it names (a port of
// game_itemtooltip/tooltiplogic.lua L.comparable, L.compareWith, L.toScale, L.diff, L.diffText). Server tip fields: cmp = [slot, ...],
// stats = [{k, l, v, fmt, low, sc}], kind, ds (display scale of flat health / mana / damage rows).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class DiffRow
    {
        public string Key = "", Label = "", Fmt = "";
        public double D;
        public bool Better;
    }

    public static class ItemCompare
    {
        public const string BetterColor = "#6fdc6f", WorseColor = "#e86a5a", HelpColor = "#a8c8a0";

        /// <summary>Ctrl compares only wearable gear: a tip with cmp slots, a kind and numbers to compare.</summary>
        public static bool Comparable(object tip)
        {
            return tip is Dictionary<string, object> && Json.List(tip, "cmp").Count > 0 && Json.Get(tip, "kind") != null && Json.List(tip, "stats").Count > 0;
        }

        /// <summary>The inventory slots a tip may be compared in.</summary>
        public static List<int> Slots(object tip)
        {
            var o = new List<int>();
            foreach (object s in Json.List(tip, "cmp")) if (s is double d) o.Add((int)d);
            return o;
        }

        /// <summary>The worn tips of the same kind as the hovered one (a weapon is not compared with a shield). bySlot: slot to the worn item's tip,
        /// null when unknown yet; keys: slot to the worn item's cache key (the hovered item itself is left out).</summary>
        public static List<object> CompareWith(object tip, IDictionary<int, object> bySlot, string hoveredKey, IDictionary<int, string> keys)
        {
            var o = new List<object>();
            if (!Comparable(tip)) return o;
            string kind = Json.Text(tip, "kind");
            foreach (int slot in Slots(tip))
            {
                if (!bySlot.TryGetValue(slot, out object e) || e == null) continue;
                if (Json.Text(e, "kind") != kind) continue;
                if (hoveredKey != null && keys != null && keys.TryGetValue(slot, out string k) && k == hoveredKey) continue;
                o.Add(e);
            }
            return o;
        }

        /// <summary>A flat value of the other item brought to this item's display scale.</summary>
        public static double ToScale(double v, double from, double to)
        {
            if (from == to || from <= 0) return v;
            return Math.Floor(v / from * to + 0.5);
        }

        static double Ds(object tip) => Json.Get(tip, "ds") is double d && d > 0 ? d : 1;

        static bool Truthy(object v) => v != null && !(v is bool b && !b) && !(v is double d && d == 0);

        /// <summary>Differences hovered minus worn per number, in the hovered item's order, then what only the worn one has.</summary>
        public static List<DiffRow> Diff(object a, object b)
        {
            var rows = new List<DiffRow>();
            var seen = new HashSet<string>();
            var bv = new Dictionary<string, double>();
            double ads = Ds(a), bds = Ds(b);
            var bstats = Json.List(b, "stats");
            foreach (object s in bstats)
            {
                double v = Json.Number(s, "v");
                if (Truthy(Json.Get(s, "sc"))) v = ToScale(v, bds, ads);
                bv[Json.Text(s, "k")] = v;
            }
            Action<object, double> push = (s, d) =>
            {
                if (d == 0) return;
                bool low = Json.Truthy(s, "low");
                rows.Add(new DiffRow { Key = Json.Text(s, "k"), Label = Json.Text(s, "l"), Fmt = Json.Text(s, "fmt"), D = d, Better = low ? d < 0 : d > 0 });
            };
            foreach (object s in Json.List(a, "stats"))
            {
                string k = Json.Text(s, "k");
                seen.Add(k);
                push(s, Json.Number(s, "v") - (bv.TryGetValue(k, out double o) ? o : 0));
            }
            foreach (object s in bstats)
            {
                string k = Json.Text(s, "k");
                if (!seen.Contains(k)) push(s, -bv[k]);
            }
            return rows;
        }

        public static string DiffText(DiffRow row)
        {
            string sign = row.D > 0 ? "+" : "-";
            return sign + TipLines.FormatValue(Math.Abs(row.D), row.Fmt, false, false) + " " + row.Label;
        }

        /// <summary>The extra rows under the hovered tooltip: the Ctrl hint, the differences with every worn item of the same kind, the Alt hint or help.
        /// waiting: a worn item's tip was asked for and has not come yet (no "nothing equipped" then).</summary>
        public static List<TipLine> ExtraRows(object tip, bool ctrl, bool alt, List<object> others, bool waiting)
        {
            var rows = new List<TipLine>();
            bool comparable = Comparable(tip);
            if (ctrl && comparable)
            {
                foreach (object o in others)
                {
                    string name = Json.Text(o, "name");
                    rows.Add(new TipLine { Text = Loc.T("Compared with {0}", name.Length > 0 ? TipLines.Title(name) : Loc.T("equipped")), Color = TipLines.Dim, Sep = true });
                    var diffs = Diff(tip, o);
                    if (diffs.Count == 0) rows.Add(new TipLine { Text = Loc.T("No difference"), Color = TipLines.Dim });
                    foreach (var d in diffs) rows.Add(new TipLine { Text = DiffText(d), Color = d.Better ? BetterColor : WorseColor });
                }
                if (others.Count == 0 && !waiting) rows.Add(new TipLine { Text = Loc.T("Nothing equipped to compare"), Color = TipLines.Dim, Sep = true });
            }
            else if (comparable) rows.Add(new TipLine { Text = Loc.T("Hold Ctrl to compare"), Color = TipLines.Dim, Sep = true });
            var help = ItemHelp.Lines(tip);
            if (help.Count > 0)
            {
                if (alt)
                {
                    for (int i = 0; i < help.Count; i++)
                    {
                        var parts = TipLines.WrapText(help[i], 48);
                        for (int j = 0; j < parts.Count; j++) rows.Add(new TipLine { Text = parts[j], Color = HelpColor, Sep = i == 0 && j == 0 });
                    }
                }
                else rows.Add(new TipLine { Text = ItemHelp.Hint(), Color = TipLines.Dim, Sep = !(comparable && !ctrl) });
            }
            return rows;
        }
    }
}
