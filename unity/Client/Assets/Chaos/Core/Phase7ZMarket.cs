// Phase 7, track Z: price charts and price history. game_orbexchange: the price chart of the book (orbexchangeview.lua V.chart). game_market: the price history of an item key
// (marketpriceview.lua): typical price, stats, the 30-day chart, the price the Sell form suggests and its warning, the mark of a Browse row. Pure.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>One point of a price chart: units ago (hours for the Orb Exchange, days for the market), the average price and the volume.</summary>
    public struct ChartPoint
    {
        public double Ago, Price, Volume;
        public ChartPoint(double ago, double price, double volume) { Ago = ago; Price = price; Volume = volume; }
    }

    public struct ChartRect
    {
        public int X, Y, W, H;
        public bool Line;   // the price step line; else a volume bar
    }

    public static class PriceChart
    {
        public static List<ChartPoint> Points(object list)
        {
            var o = new List<ChartPoint>();
            foreach (var r in CF.Rows(list)) o.Add(new ChartPoint(CF.N(r, "h"), CF.N(r, "p"), CF.N(r, "v")));
            return o;
        }

        /// <summary>The rectangles of the chart in a w x h box: the price as a step line of 2 px and the volume as bars at the bottom (a quarter of the height at most).
        /// Points oldest first; `units` is the width of the axis (24 hours, 30 days).</summary>
        public static List<ChartRect> Rects(IList<ChartPoint> pts, int units, int w, int h)
        {
            var o = new List<ChartRect>();
            if (pts == null || pts.Count == 0 || w <= 0 || h <= 0) return o;
            if (units <= 0) units = 24;
            double lo = double.MaxValue, hi = double.MinValue, vmax = 0;
            foreach (var p in pts) { lo = Math.Min(lo, p.Price); hi = Math.Max(hi, p.Price); vmax = Math.Max(vmax, p.Volume); }
            double pad = (hi - lo) * 0.1;
            if (pad == 0) pad = hi > 0 ? hi * 0.05 : 1;
            lo -= pad; hi += pad;
            int lineH = h - h / 4 - 2;
            double slot = (double)w / units;
            Func<double, int> xOf = ago => (int)Math.Floor((units - 1 - ago) * slot);
            Func<double, int> yOf = price => (int)Math.Floor((hi - price) / (hi - lo) * (lineH - 2));
            for (int i = 0; i < pts.Count; i++)
            {
                var pt = pts[i];
                int x0 = xOf(pt.Ago);
                int x1 = i < pts.Count - 1 ? xOf(pts[i + 1].Ago) : w;
                int y = yOf(pt.Price);
                o.Add(new ChartRect { X = x0, Y = y, W = Math.Max(2, x1 - x0), H = 2, Line = true });
                if (i < pts.Count - 1)
                {
                    int y2 = yOf(pts[i + 1].Price);
                    o.Add(new ChartRect { X = x1, Y = Math.Min(y, y2), W = 2, H = Math.Abs(y2 - y) + 2, Line = true });
                }
                if (vmax > 0)
                {
                    int vh = Math.Max(1, (int)Math.Floor(pt.Volume / vmax * (h / 4)));
                    o.Add(new ChartRect { X = x0 + 1, Y = h - vh, W = Math.Max(1, (int)Math.Floor(slot) - 2), H = vh, Line = false });
                }
            }
            return o;
        }

        /// <summary>The scale texts: the highest and the lowest price shown (short numbers), null without points.</summary>
        public static bool Scale(IList<ChartPoint> pts, out string high, out string low)
        {
            high = low = "";
            if (pts == null || pts.Count == 0) return false;
            double lo = double.MaxValue, hi = double.MinValue;
            foreach (var p in pts) { lo = Math.Min(lo, p.Price); hi = Math.Max(hi, p.Price); }
            high = CF.Short(hi); low = CF.Short(lo);
            return true;
        }
    }

    public sealed class PriceLine { public string Text = "", Tone = ""; }

    /// <summary>An item dragged from a bag onto the Sell tab (market.lua onDropItem): the bag item at the position, then the entry of the picker list with the same per-item id,
    /// else the same look and count.</summary>
    public static class MarketDrop
    {
        public static Item BagItem(IDictionary<byte, Container> containers, Pos p)
        {
            if (containers == null || p.X != 0xFFFF || p.Y < 0x40 || p.Y >= 0x50) return null;
            if (!containers.TryGetValue((byte)(p.Y - 0x40), out var c)) return null;
            int idx = p.Z - c.FirstIndex;
            return idx >= 0 && idx < c.Items.Count ? c.Items[idx] : null;
        }

        /// <summary>The picker entry for the dropped item, null when the list has none.</summary>
        public static object Match(IEnumerable<object> entries, int clientId, int count, ulong iid)
        {
            foreach (var e in entries)
            {
                if (iid > 0 && CF.T(e, "iid") == iid.ToString(CultureInfo.InvariantCulture)) return e;
                if (iid == 0 && CF.I(e, "item") == clientId && CF.I(e, "count") == Math.Max(1, count)) return e;
            }
            return null;
        }
    }

    /// <summary>The price history texts of the market window (marketpriceview.lua).</summary>
    public static class MarketPrices
    {
        public static string CurName(string cur, double n) => cur == "coins" ? (n == 1 ? Loc.T("Chaos Coin") : Loc.T("Chaos Coins")) : Loc.T("gold");

        public static string Ago(object seconds)
        {
            if (!(seconds is double s)) return "";
            if (s < 60) return Loc.T("just now");
            if (s < 3600) return Loc.T("{0}m ago", (long)Math.Floor(s / 60));
            if (s < 86400) return Loc.T("{0}h ago", (long)Math.Floor(s / 3600));
            return Loc.T("{0}d ago", (long)Math.Floor(s / 86400));
        }

        /// <summary>"Rare - iLvl 60-69": the key the stats are of.</summary>
        public static string KeyText(int rarity, string band)
        {
            var parts = new List<string>();
            if (rarity > 0) { string n = MarketMath.RarityName(rarity); if (n != null) parts.Add(n); }
            if (!string.IsNullOrEmpty(band)) parts.Add(band);
            return string.Join(" - ", parts);
        }

        static int N(object o, string k, int d = 0) => CF.G(o, k) is double v ? (int)v : d;

        public static PriceLine Typical(object s, string cur)
        {
            if (s == null || (N(s, "n30") == 0 && N(s, "n7") == 0)) return new PriceLine { Text = Loc.T("No sales of this item yet."), Tone = "dim" };
            if (!(CF.G(s, "typical") is double t) || t <= 0)
            {
                int have = Math.Max(N(s, "n7"), N(s, "n30"));
                return new PriceLine { Text = Loc.T("Typical price: not enough sales yet ({0} of {1}).", have, N(s, "need", 5)), Tone = "dim" };
            }
            string basis = CF.T(s, "basis") == "7d" ? Loc.T("median of {0} sales, 7 days", N(s, "n7")) : Loc.T("daily medians of {0} sales, {1} days", N(s, "n30"), N(s, "days", 30));
            return new PriceLine { Text = Loc.T("Typical price: {0} {1} each ({2})", SFmt.Money(t), CurName(cur, t), basis), Tone = "gold" };
        }

        /// <summary>The stats as lines: typical, last sale, 7 days (median, range, volume), lowest and highest.</summary>
        public static List<PriceLine> Stats(object s, string cur)
        {
            var o = new List<PriceLine> { Typical(s, cur) };
            if (s == null) return o;
            string c = CurName(cur, 2);
            if (CF.G(s, "last") is double last) o.Add(new PriceLine { Text = Loc.T("Last sale: {0} {1}, {2}", SFmt.Money(last), c, Ago(CF.G(s, "lastAgo"))), Tone = "text" });
            int n7 = N(s, "n7");
            if (n7 > 0)
            {
                int units = N(s, "units7", n7);
                o.Add(new PriceLine { Text = Loc.T("7 days: median {0}, {1} sale{2} ({3} unit{4})", SFmt.Money(CF.N(s, "median7")), n7, n7 == 1 ? "" : "s", units, units == 1 ? "" : "s"), Tone = "text" });
                if (CF.G(s, "lo") is double lo && CF.G(s, "hi") is double hi && (lo != CF.N(s, "min7") || hi != CF.N(s, "max7")))
                    o.Add(new PriceLine { Text = Loc.T("Usual range: {0} - {1} (lowest {2}, highest {3})", SFmt.Money(lo), SFmt.Money(hi), SFmt.Money(CF.N(s, "min7")), SFmt.Money(CF.N(s, "max7"))), Tone = "dim" });
                else
                    o.Add(new PriceLine { Text = Loc.T("Lowest {0}, highest {1}", SFmt.Money(CF.N(s, "min7")), SFmt.Money(CF.N(s, "max7"))), Tone = "dim" });
            }
            else if (N(s, "n30") > 0) o.Add(new PriceLine { Text = Loc.T("No sales in 7 days; {0} in {1} days.", N(s, "n30"), N(s, "days", 30)), Tone = "dim" });
            return o;
        }

        static bool Has(object s) => s != null && (N(s, "n30") > 0 || N(s, "n7") > 0);

        /// <summary>Which currency the detail shows first: the wanted one when it has sales, else gold, else coins.</summary>
        public static string Currency(object data, string want)
        {
            object g = CF.G(data, "gold"), c = CF.G(data, "coins");
            if (want == "coins" && Has(c)) return "coins";
            if (want == "gold" && Has(g)) return "gold";
            if (Has(g)) return "gold";
            if (Has(c)) return "coins";
            return "gold";
        }

        /// <summary>The price the Sell form suggests: the typical price per unit rounded down to 3 significant digits (never under the market minimum) times the units; -1 without one.</summary>
        public static long Suggest(double typical, long count, long minPrice)
        {
            if (typical <= 0) return -1;
            long unit = (long)Math.Floor(typical);
            if (unit >= 1000)
            {
                long step = (long)Math.Pow(10, unit.ToString(CultureInfo.InvariantCulture).Length - 3);
                unit = unit / step * step;
            }
            long total = unit * Math.Max(1, count);
            if (minPrice > 0 && total < minPrice) total = minPrice;
            return total;
        }

        /// <summary>The warning for an asking price of count units, null near the typical price (or without one).</summary>
        public static PriceLine SellWarning(double ask, long count, double typical, double warnLow, double warnHigh, string cur)
        {
            if (ask <= 0 || typical <= 0) return null;
            double unit = Math.Floor(ask / Math.Max(1, count));
            double r = unit / typical;
            long pct = (long)Math.Floor(r * 100 + 0.5);
            if (r <= warnLow) return new PriceLine { Text = Loc.T("Far below the typical price: {0}% of {1} {2} each. Is that what you want?", pct, SFmt.Money(typical), CurName(cur, typical)), Tone = "warn" };
            if (r >= warnHigh) return new PriceLine { Text = Loc.T("Far above the typical price: {0}% of {1} {2} each; it may not sell.", pct, SFmt.Money(typical), CurName(cur, typical)), Tone = "warn" };
            return null;
        }

        /// <summary>A Browse row's mark (the server sets typ, tcur and pm = low or high): text and tone, null without one.</summary>
        public static PriceLine RowMark(object offer)
        {
            string pm = CF.T(offer, "pm");
            double typ = CF.N(offer, "typ");
            if (pm.Length == 0 || typ <= 0) return null;
            double price = CF.T(offer, "tcur") == "coins" ? CF.N(offer, "coins") : CF.N(offer, "gold");
            double unit = Math.Floor(price / Math.Max(1, CF.N(offer, "count") > 0 ? CF.N(offer, "count") : 1));
            long diff = (long)Math.Floor(Math.Abs(unit / typ - 1) * 100 + 0.5);
            return pm == "low" ? new PriceLine { Text = Loc.T("{0}% under typical", diff), Tone = "good" } : new PriceLine { Text = Loc.T("{0}% over typical", diff), Tone = "bad" };
        }

        /// <summary>The tooltip line of a row's typical price, null without one.</summary>
        public static string RowTypical(object offer)
        {
            if (!(CF.G(offer, "typ") is double typ)) return null;
            return Loc.T("Typical price: {0} {1} each", SFmt.Money(typ), CurName(CF.T(offer, "tcur"), typ));
        }
    }
}
