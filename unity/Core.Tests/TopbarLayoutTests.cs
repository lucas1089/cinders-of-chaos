// The top menu row layout (Core/TopbarLayout.cs): buttons sized to their labels, right-aligned, wrapped when too wide, English and pt-BR.
using System;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class TopbarLayoutTests
    {
        // label widths in pixels at the default button font (about 8 px a letter)
        static float[] Widths(params string[] labels) => labels.Select(l => l.Length * 8f).ToArray();

        static readonly string[] En = { "Character", "Hunt", "Adventure", "Economy", "Social", "System", "Windows" };
        static readonly string[] Pt = { "Personagem", "Caça", "Aventura", "Economia", "Social", "Sistema", "Janelas" };

        public static void Run(Action<bool, string> check)
        {
            foreach (var set in new[] { En, Pt })
            {
                string tag = set == En ? "en" : "pt-BR";
                var w = Widths(set);
                var cells = TopbarLayout.Fit(w, 10f, 56f, 4f, 264f, 1176f);
                bool fits = true, ordered = true;
                for (int i = 0; i < cells.Length; i++)
                {
                    if (cells[i].W < w[i] + 20f) fits = false;
                    if (i > 0 && cells[i].X < cells[i - 1].X + cells[i - 1].W + 4f - 0.01f) ordered = false;
                }
                check(fits, "topbar " + tag + ": every button wider than its label plus padding");
                check(ordered && Math.Abs(cells[cells.Length - 1].X + cells[cells.Length - 1].W - 1176f) < 0.01f, "topbar " + tag + ": one row, right-aligned at the Log out edge");
                check(TopbarLayout.Rows(cells) == 1 && cells[0].X >= 264f, "topbar " + tag + ": one row on 1280 px");
            }

            // too narrow: wraps, no row crosses the left limit or the right edge
            var narrow = TopbarLayout.Fit(Widths(Pt), 10f, 56f, 4f, 264f, 800f);
            check(TopbarLayout.Rows(narrow) == 2, "topbar: 2 rows when 7 pt-BR buttons do not fit in 536 px");
            check(narrow.All(c => c.X >= 264f - 0.01f && c.X + c.W <= 800f + 0.01f), "topbar: wrapped buttons stay inside the limits");
            check(narrow.Where(c => c.Row == 0).Max(c => c.X + c.W) <= 800f + 0.01f && narrow.Where(c => c.Row == 1).Max(c => c.X + c.W) <= 800f + 0.01f, "topbar: both rows end at the right edge or before");
            check(narrow.Select(c => c.Row).SequenceEqual(narrow.Select(c => c.Row).OrderBy(r => r)), "topbar: rows fill in order");

            // a label wider than the whole row still gets a row of its own
            var wide = TopbarLayout.Fit(new[] { 900f, 40f }, 10f, 56f, 4f, 0f, 500f);
            check(wide[0].Row == 0 && wide[1].Row == 1, "topbar: an over-wide label sits alone on its row");
            check(TopbarLayout.Fit(new float[0], 10f, 56f, 4f, 0f, 500f).Length == 0, "topbar: no buttons, no cells");

            // the Candlemarks counter beside the row: the old fixed spot (7 buttons of 76 px) ran into "Character" on 1280 px (live server, 2026-11-09)
            var en = TopbarLayout.Fit(Widths(En), 10f, 56f, 4f, 264f, 1176f);
            float rowMin = en[0].X, rowMax = en[en.Length - 1].X + en[en.Length - 1].W;
            TopbarLayout.SideSlot(rowMin, rowMax, 38f, 264f, 210f, 6f, 0f, out float sx, out float sy);
            check(sy == 12f && sx + 210f + 6f <= rowMin + 0.01f && sx >= 264f, "candle counter: left of the first menu button on 1280 px (" + sx + ".." + (sx + 210f) + ", row from " + rowMin + ")");
            TopbarLayout.SideSlot(narrow.Min(c => c.X), 800f, 70f, 264f, 210f, 6f, 0f, out sx, out sy);
            check(sy == 76f && Math.Abs(sx + 210f - 800f) < 0.01f, "candle counter: under a wrapped row, right-aligned, when no room is left of it");
            TopbarLayout.SideSlot(0f, 0f, 0f, 264f, 210f, 6f, 123f, out sx, out sy);
            check(sx == 123f && sy == 12f, "candle counter: the fallback spot before the row was drawn");

            // minimum width for short labels
            check(TopbarLayout.Fit(new[] { 8f }, 10f, 56f, 4f, 0f, 500f)[0].W == 56f, "topbar: minimum button width");

            // buff cells: never below the base size, grow for a wide short name or timer
            check(TopbarLayout.CellWidth(18f, 14f, 26f, 6f) == 26f, "buff cell: base size for small text");
            check(TopbarLayout.CellWidth(30f, 28f, 26f, 6f) == 36f, "buff cell: widens for the name");
            check(TopbarLayout.CellWidth(20f, 34f, 26f, 6f) == 40f, "buff cell: widens for the timer");
            var flow = BuffBar.Flow(5, 100, 40, 32, 2, out int height);
            check(flow.Count == 5 && flow[1].x == 42 && flow[2].x == 0 && flow[2].y == 34 && height == 3 * 34 - 2, "buff flow: 2 wide cells per 100 px row, 3 rows");
            for (int i = 1; i < flow.Count; i++)
                if (flow[i].y == flow[i - 1].y) check(flow[i].x - flow[i - 1].x >= 40 + 2, "buff flow: cells in a row do not overlap " + i);
        }
    }
}
