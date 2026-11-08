// Social and market windows (O433 phase 4, track M): the shared model of a "rows" window. Most of these windows of the main client are lists of
// text rows with a few buttons, tabs, a status line and a small form (guild, guild wars, party finder, factions ...). A panel builds its rows from the
// server's last message; the Unity window (SocialWindow) draws them. Every panel is pure C#: messages in, requests out through ExtOpcodes.
//   Rows:   section heading, text, row (label, right text, up to 3 buttons), input (text field), combo (a button that cycles the options), bar.
//   Panels: Market (221), Guild (252), GuildWar (197), PartyFinder (208), GroupQueue (160), Inspect (240), Leaderboard (229), Factions (215), Conquest (167).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    public enum RowKind { Section, Text, Row, Input, Combo, Bar, Chart }

    public sealed class SocialButton
    {
        public string Text = "", Tip = "";
        public bool Enabled = true;
        public Action Click = delegate { };
    }

    /// <summary>One row of a panel. Tone is a name (dim, good, warn, bad, gold, text, coins, unique) or a #rrggbb colour.</summary>
    public sealed class SocialRow
    {
        public RowKind Kind;
        public string Text = "", Right = "", Tone = "", Key = "", Hint = "", Tip = "", Sub = "";
        public int Percent;
        public uint ItemId;
        public int Count = 1;
        public string Frame;
        public object ItemTip;
        /// <summary>Lines added under the item tooltip while the pointer is over the row (the market's matched modifiers).</summary>
        public List<TipLine> TipExtra;
        /// <summary>RowKind.Chart: the points (price chart) and the width of the axis in units.</summary>
        public List<ChartPoint> Points;
        public int Units = 30;
        /// <summary>Called by the window while the pointer is over the row (a panel asks the server for a tooltip).</summary>
        public Action Hover;
        public List<SocialButton> Buttons = new List<SocialButton>();
        public List<string> Options = new List<string>();
        public override string ToString() => Kind + ":" + Text;
    }

    /// <summary>The rows of a panel, built with one call per row.</summary>
    public sealed class RowList
    {
        public readonly List<SocialRow> Rows = new List<SocialRow>();

        public SocialRow Section(string text) { var r = new SocialRow { Kind = RowKind.Section, Text = text }; Rows.Add(r); return r; }
        public SocialRow Text(string text, string tone = "") { var r = new SocialRow { Kind = RowKind.Text, Text = text, Tone = tone }; Rows.Add(r); return r; }
        public SocialRow Bar(string text, int percent) { var r = new SocialRow { Kind = RowKind.Bar, Text = text, Percent = Math.Max(0, Math.Min(100, percent)) }; Rows.Add(r); return r; }
        public SocialRow Input(string label, string key, string hint = "") { var r = new SocialRow { Kind = RowKind.Input, Text = label, Key = key, Hint = hint }; Rows.Add(r); return r; }
        public SocialRow Combo(string label, string key, IEnumerable<string> options) { var r = new SocialRow { Kind = RowKind.Combo, Text = label, Key = key }; r.Options.AddRange(options); Rows.Add(r); return r; }

        public SocialRow Row(string label, string right = "", string tone = "")
        {
            var r = new SocialRow { Kind = RowKind.Row, Text = label, Right = right, Tone = tone };
            Rows.Add(r);
            return r;
        }

        /// <summary>A price chart row (Phase7ZMarket.cs PriceChart): Text is the caption.</summary>
        public SocialRow Chart(string text, List<ChartPoint> points, int units) { var r = new SocialRow { Kind = RowKind.Chart, Text = text, Points = points, Units = units }; Rows.Add(r); return r; }

        public SocialRow Add(SocialRow r) { Rows.Add(r); return r; }
    }

    public static class RowExt
    {
        public static SocialRow Btn(this SocialRow r, string text, bool enabled, Action click, string tip = "")
        {
            r.Buttons.Add(new SocialButton { Text = text, Enabled = enabled, Click = click ?? delegate { }, Tip = tip ?? "" });
            return r;
        }

        public static SocialRow Item(this SocialRow r, int clientId, int count = 1, string frame = null, object tip = null)
        {
            r.ItemId = clientId > 0 && clientId < 65536 ? (uint)clientId : 0;
            r.Count = Math.Max(1, count);
            r.Frame = frame;
            r.ItemTip = tip;
            return r;
        }
    }

    /// <summary>A window's model. Messages come in through the ExtOpcodes handler a subclass registers; Changed tells the window.</summary>
    public abstract class SocialPanel
    {
        public bool Visible;
        public string Status = "", StatusTone = "dim";
        public string Header1 = "", Header2 = "";
        /// <summary>Tabs: key and shown English text. Empty for a window without tabs.</summary>
        public readonly List<KeyValuePair<string, string>> Tabs = new List<KeyValuePair<string, string>>();
        public string Tab = "";
        /// <summary>Texts of the input rows and the chosen index of the combo rows, by key.</summary>
        public readonly Dictionary<string, string> Form = new Dictionary<string, string>();
        public Action Changed = delegate { };

        public abstract List<SocialRow> BuildRows();

        public virtual void Show() { Visible = true; }
        public virtual void Hide() { Visible = false; }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public virtual void SelectTab(string key) { Tab = key; Changed(); }
        /// <summary>An input or combo row changed.</summary>
        public virtual void OnForm(string key) { }
        /// <summary>A new character must not see this one's data.</summary>
        public virtual void Clear() { Visible = false; Status = ""; Header1 = Header2 = ""; Form.Clear(); }

        public string Text(string key) => Form.TryGetValue(key, out var v) ? v : "";
        public int Index(string key, int fallback = 0) => int.TryParse(Text(key), NumberStyles.Integer, CultureInfo.InvariantCulture, out int i) ? i : fallback;

        public void Say(string text, bool ok) { Status = text ?? ""; StatusTone = ok ? "good" : "bad"; Changed(); }
    }

    /// <summary>Texts and numbers the social windows share.</summary>
    public static class SFmt
    {
        /// <summary>1234567 -> "1,234,567".</summary>
        public static string Money(double n)
        {
            long v = (long)Math.Floor(double.IsNaN(n) ? 0 : n);
            return v.ToString("N0", CultureInfo.InvariantCulture);
        }

        /// <summary>93784 s -> "1d 2h", 4980 -> "1h 23m", 45 -> "0m".</summary>
        public static string Duration(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
            if (d > 0) return d + "d " + h + "h";
            if (h > 0) return h + "h " + m + "m";
            return m + "m";
        }

        /// <summary>75 -> "1:15".</summary>
        public static string Clock(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            return (s / 60) + ":" + (s % 60).ToString("00", CultureInfo.InvariantCulture);
        }

        /// <summary>"1500", "1,500", "5k", "2.5m", "1b" -> the number; an empty text is 0; -1 when it is no whole non-negative number.</summary>
        public static long ParseAmount(string text)
        {
            var sb = new StringBuilder();
            foreach (char c in (text ?? "").ToLowerInvariant()) if (c != ',' && !char.IsWhiteSpace(c)) sb.Append(c);
            string t = sb.ToString();
            if (t.Length == 0) return 0;
            long mul = 1;
            char last = t[t.Length - 1];
            if (last == 'k') mul = 1000; else if (last == 'm') mul = 1000000; else if (last == 'b') mul = 1000000000;
            if (mul != 1) t = t.Substring(0, t.Length - 1);
            if (t.Length == 0) return -1;
            int dots = 0;
            foreach (char c in t) { if (c == '.') dots++; else if (c < '0' || c > '9') return -1; }
            if (dots > 1 || t[0] == '.') return -1;
            if (!decimal.TryParse(t, NumberStyles.Number, CultureInfo.InvariantCulture, out decimal v)) return -1;
            decimal total = v * mul;
            if (total != decimal.Floor(total) || total > 9000000000000000m) return -1;
            return (long)total;
        }

        public static string Pct(double v) => Math.Abs(v - Math.Floor(v)) < 1e-9 ? ((long)v).ToString(CultureInfo.InvariantCulture) : v.ToString("0.0", CultureInfo.InvariantCulture);

        /// <summary>The rows of a server list that are objects (a malformed entry is left out).</summary>
        public static List<object> Rows(object o, string key)
        {
            var r = new List<object>();
            foreach (object x in Json.List(o, key)) if (x is Dictionary<string, object>) r.Add(x);
            return r;
        }

        public static bool Has(object o, string key) => Json.Get(o, key) != null;
        public static bool IsMap(object o) => o is Dictionary<string, object>;

        public static Dictionary<string, object> Map(params object[] kv)
        {
            var d = new Dictionary<string, object>();
            for (int i = 0; i + 1 < kv.Length; i += 2) d[(string)kv[i]] = kv[i + 1];
            return d;
        }

        /// <summary>A rarity colour of a market or tooltip row: the unique colour first, else the rarity's.</summary>
        public static string RarityTone(int rarity, bool unique) => unique ? ItemRarity.UniqueColor : (ItemRarity.Color(ItemRarity.Canon(rarity)) ?? "text");
    }
}
