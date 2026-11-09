// Pure layout of the top menu row: each button is as wide as its label plus padding, the row is right-aligned and ends where
// the Log out button starts. When the row does not fit between the left limit and the right edge it wraps to more rows.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public struct TopbarCell
    {
        public float X, W;
        public int Row;
    }

    public static class TopbarLayout
    {
        /// <summary>Button cells for the label widths. Each row is right-aligned at rightEdge. Rows fill in order, left to right.</summary>
        public static TopbarCell[] Fit(IList<float> labelWidths, float padding, float minWidth, float gap, float leftLimit, float rightEdge)
        {
            int n = labelWidths.Count;
            var widths = new float[n];
            for (int i = 0; i < n; i++) widths[i] = Math.Max(minWidth, labelWidths[i] + 2 * padding);
            float avail = Math.Max(1f, rightEdge - leftLimit);
            var cells = new TopbarCell[n];
            int start = 0, row = 0;
            while (start < n)
            {
                int end = start;
                float used = 0;
                while (end < n)
                {
                    float add = widths[end] + (end > start ? gap : 0);
                    if (end > start && used + add > avail) break;
                    used += add;
                    end++;
                }
                float x = rightEdge - used;
                for (int i = start; i < end; i++)
                {
                    cells[i] = new TopbarCell { X = x, W = widths[i], Row = row };
                    x += widths[i] + gap;
                }
                start = end;
                row++;
            }
            return cells;
        }

        public static int Rows(TopbarCell[] cells)
        {
            int r = 0;
            foreach (var c in cells) r = Math.Max(r, c.Row + 1);
            return r;
        }

        /// <summary>Where a box of `width` next to the menu row goes (the Candlemarks counter): left of the row's first button, `gap` apart, when that stays
        /// right of `leftLimit`; else under the row, right-aligned with it. barXMax 0 or less: the row is not drawn yet, `fallbackX` is used.</summary>
        public static void SideSlot(float barXMin, float barXMax, float barYMax, float leftLimit, float width, float gap, float fallbackX, out float x, out float y)
        {
            if (barXMax <= 0) { x = fallbackX; y = 12; return; }
            x = barXMin - gap - width;
            y = 12;
            if (x >= leftLimit) return;
            x = barXMax - width;
            y = barYMax + gap;
        }

        /// <summary>Cell width for a buff icon: wide enough for the short name and the timer, never below the base size.</summary>
        public static float CellWidth(float labelWidth, float timerWidth, float baseSize, float padding = 4f) =>
            Math.Max(baseSize, Math.Max(labelWidth, timerWidth) + padding);
    }
}
