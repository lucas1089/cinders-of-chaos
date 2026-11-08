// Phase 7 track X, hotbar: the slot count and scale options and the sizes that follow from them, the fit into a narrow window, and the
// plan of the side slots (Q and E). A port of the pure rules of game_hotbar (hotbar_logic.lua: COUNTS, clampScale, metrics, fit, slotPlan,
// keyLabel, settingsFor). The main client also has the iron frame art and the globes docked to the bar; the Unity bar keeps its plain
// frame and its own globes (Core/OverlayArt.cs).
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>The saved options of one character's hotbar: how many main row slots (6, 8, 10 or 12) and the scale in percent (75 to 125).</summary>
    public struct HotbarOptions
    {
        public int Count, Scale;
        public static readonly int[] Counts = { 6, 8, 10, 12 };
        public const int ScaleMin = 75, ScaleMax = 125, ScaleStep = 5, DefaultScale = 100;
        /// <summary>The Unity bar always had twelve slots, so that stays the default (the main client starts with eight).</summary>
        public const int DefaultCount = 12;
        public const int FitMinScale = 60, FitMinCount = 4;

        public static HotbarOptions Default => new HotbarOptions { Count = DefaultCount, Scale = DefaultScale };

        /// <summary>The nearest allowed slot count; a bad value gives the default.</summary>
        public static int ClampCount(double v)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return DefaultCount;
            int best = Counts[0]; double bd = double.MaxValue;
            foreach (int c in Counts)
            {
                double d = Math.Abs(c - v);
                if (d < bd) { best = c; bd = d; }
            }
            return best;
        }

        /// <summary>The scale rounded to a step of 5 and kept in 75 to 125; a bad value gives 100.</summary>
        public static int ClampScale(double v)
        {
            if (double.IsNaN(v) || double.IsInfinity(v)) return DefaultScale;
            int r = (int)Math.Floor(v / ScaleStep + 0.5) * ScaleStep;
            return Math.Max(ScaleMin, Math.Min(ScaleMax, r));
        }

        public static HotbarOptions Parse(string saved)
        {
            var o = Default;
            if (string.IsNullOrEmpty(saved)) return o;
            string[] p = saved.Split('|');
            if (p.Length >= 1 && double.TryParse(p[0], NumberStyles.Float, CultureInfo.InvariantCulture, out double c)) o.Count = ClampCount(c);
            if (p.Length >= 2 && double.TryParse(p[1], NumberStyles.Float, CultureInfo.InvariantCulture, out double s)) o.Scale = ClampScale(s);
            return o;
        }

        public string Encode() => ClampCount(Count).ToString(CultureInfo.InvariantCulture) + "|" + ClampScale(Scale).ToString(CultureInfo.InvariantCulture);
    }

    /// <summary>The size of the bar for its options. Every length is rounded to whole pixels at the scale.</summary>
    public struct HotbarMetrics
    {
        public int Count, Scale;
        public int SlotW, SlotH, Gap, SideW, SideGap, Pad;
        public int Width;
        /// <summary>Distance from one slot's left edge to the next one's.</summary>
        public int Pitch => SlotW + Gap;
    }

    public static class HotbarLayout
    {
        // the Unity slot at 100 percent: 34 x 40 with a 2 px gap (the pitch of 36 it always had), round side slots of 34 with a gap of 6
        public const int BaseSlotW = 34, BaseSlotH = 40, BaseGap = 2, BaseSide = 34, BaseSideGap = 6, BasePad = 4;

        public static HotbarMetrics Metrics(int count, int scalePercent, bool raw = false)
        {
            int cnt = raw ? Math.Max(1, count) : HotbarOptions.ClampCount(count);
            int pct = raw ? scalePercent : HotbarOptions.ClampScale(scalePercent);
            double s = pct / 100.0;
            int Px(int v) => (int)Math.Floor(v * s + 0.5);
            var m = new HotbarMetrics { Count = cnt, Scale = pct, SlotW = Px(BaseSlotW), SlotH = Px(BaseSlotH), Gap = Px(BaseGap), SideW = Px(BaseSide), SideGap = Px(BaseSideGap), Pad = Px(BasePad) };
            int cells = cnt * m.SlotW + (cnt - 1) * m.Gap;
            m.Width = 2 * m.Pad + 2 * (m.SideW + m.SideGap) + cells;
            return m;
        }

        /// <summary>The options that fit `available` pixels of width: the scale goes down in steps of 5 to 60 first, then the count down by 2 (never under 4).
        /// Returns the fitted metrics and whether anything was cut.</summary>
        public static HotbarMetrics Fit(HotbarOptions opts, double available, out bool cut)
        {
            int count = HotbarOptions.ClampCount(opts.Count), scale = HotbarOptions.ClampScale(opts.Scale);
            cut = false;
            while (Metrics(count, scale, true).Width > available && scale > HotbarOptions.FitMinScale) { scale = Math.Max(HotbarOptions.FitMinScale, scale - HotbarOptions.ScaleStep); cut = true; }
            while (Metrics(count, scale, true).Width > available && count - 2 >= HotbarOptions.FitMinCount) { count -= 2; cut = true; }
            return Metrics(count, scale, true);
        }

        /// <summary>The slots the bar draws: 0 .. count-1 in the row, then the Q socket (12) and the E socket (13) at the sides. The sockets use slots 12 and 13
        /// whatever the count is, so a slot never changes its spell when the count changes; slots past the count are hidden, not cleared.</summary>
        public static List<int> Shown(int count)
        {
            var list = new List<int>();
            for (int i = 0; i < Math.Min(count, HotbarModel.Count); i++) list.Add(i);
            return list;
        }

        /// <summary>The key label of a slot: F1 to F12 for the row, Q and E for the sockets.</summary>
        public static string KeyLabel(int slot) => slot == HotbarModel.SideQ ? "Q" : slot == HotbarModel.SideE ? "E" : slot >= 0 && slot < HotbarModel.Count ? "F" + (slot + 1).ToString(CultureInfo.InvariantCulture) : "";

        /// <summary>The slot a bare key presses: F1 to F12 (names "F1".."F12"), Q and E for the sockets; -1 for any other key name.</summary>
        public static int SlotOfKey(string keyName)
        {
            if (keyName == "Q") return HotbarModel.SideQ;
            if (keyName == "E") return HotbarModel.SideE;
            if (keyName != null && keyName.Length >= 2 && keyName[0] == 'F' && int.TryParse(keyName.Substring(1), NumberStyles.None, CultureInfo.InvariantCulture, out int n) && n >= 1 && n <= HotbarModel.Count) return n - 1;
            return -1;
        }

        /// <summary>The slot of a point in the bar, -1 outside every slot. The row's slots are `count` cells from `rowX`; the sockets stand left and right of it.</summary>
        public static int SlotAt(HotbarMetrics m, double x, double y, double barTop)
        {
            if (y < barTop || y >= barTop + m.SlotH) return -1;
            double left = m.Pad;
            if (x >= left && x < left + m.SideW) return HotbarModel.SideQ;
            double rowX = left + m.SideW + m.SideGap;
            for (int i = 0; i < m.Count; i++)
            {
                double cx = rowX + i * m.Pitch;
                if (x >= cx && x < cx + m.SlotW) return i;
            }
            double rightX = rowX + m.Count * m.Pitch - m.Gap + m.SideGap;
            if (x >= rightX && x < rightX + m.SideW) return HotbarModel.SideE;
            return -1;
        }

        /// <summary>The left edge of a slot from the bar's left edge (the row after the Q socket, E after the row).</summary>
        public static double SlotX(HotbarMetrics m, int slot)
        {
            double rowX = m.Pad + m.SideW + m.SideGap;
            if (slot == HotbarModel.SideQ) return m.Pad;
            if (slot == HotbarModel.SideE) return rowX + m.Count * m.Pitch - m.Gap + m.SideGap;
            return rowX + slot * m.Pitch;
        }
    }
}
