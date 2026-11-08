// Pure parts of two panels (phase 6, track V): the bag panel (client game_bagpanel bagpanel_core.lua: its tabs and the coin counts) and the party frames
// settings (client game_partyframes partymath.lua: the settings, scale, the height of a frame, the buff row).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    // ============================================================================================================ bag panel
    public sealed class BagTab
    {
        public string Id = "", Text = "", Window = "";
    }

    public static class BagPanel
    {
        /// <summary>Coin items by client id and what each is worth in gold.</summary>
        public static readonly Dictionary<int, long> Coins = new Dictionary<int, long> { { 3031, 1 }, { 3035, 100 }, { 3043, 10000 } };

        /// <summary>The tabs of the panel: Equip is the panel itself; the others open a window of the client (its class name). A tab shows only when its window exists.
        /// The main client's Buffs tab opens its buff bar window; here the buffs hang under the plate, so there is no such tab.</summary>
        public static readonly BagTab[] AllTabs =
        {
            new BagTab { Id = "equip", Text = "Equip" },
            new BagTab { Id = "quest", Text = "Quest", Window = "QuestLogWindow" },
            new BagTab { Id = "status", Text = "Stats", Window = "SkillsWindow" },
            new BagTab { Id = "shop", Text = "Shop", Window = "StoreWindow" },
        };

        public static List<BagTab> Tabs(Func<string, bool> hasWindow)
        {
            var o = new List<BagTab>();
            foreach (var t in AllTabs) if (t.Window.Length == 0 || (hasWindow != null && hasWindow(t.Window))) o.Add(t);
            return o;
        }

        /// <summary>The widths of the tab buttons: they share the row by the length of their text.</summary>
        public static float[] TabWidths(float[] textWidths, float room)
        {
            var o = new float[textWidths.Length];
            float total = 0;
            foreach (float w in textWidths) total += w + 6;
            float avail = room - textWidths.Length;
            for (int i = 0; i < o.Length; i++) o[i] = total > 0 && avail > 0 ? (float)Math.Floor((textWidths[i] + 6) * avail / total) : textWidths[i] + 6;
            return o;
        }

        /// <summary>The gold in a list of (client id, count) items: gold, platinum and crystal coins.</summary>
        public static long Gold(IEnumerable<KeyValuePair<int, int>> items)
        {
            long sum = 0;
            foreach (var it in items)
                if (Coins.TryGetValue(it.Key, out long v)) sum += v * Math.Max(1, it.Value);
            return sum;
        }

        /// <summary>The coins of each kind (gold, platinum, crystal) in the list, for the three counters.</summary>
        public static long[] CoinCounts(IEnumerable<KeyValuePair<int, int>> items)
        {
            var c = new long[3];
            foreach (var it in items)
            {
                int n = Math.Max(1, it.Value);
                if (it.Key == 3031) c[0] += n; else if (it.Key == 3035) c[1] += n; else if (it.Key == 3043) c[2] += n;
            }
            return c;
        }

        /// <summary>The panel's figure: where the outfit stands (centre of the paper doll) and how big; the doll keeps its slots, the figure sits behind them.</summary>
        public static float FigureSize(float dollWidth, float dollHeight) => Math.Max(32f, Math.Min(dollWidth, dollHeight) * 0.9f);
    }

    // ============================================================================================================ party frames settings
    public sealed class PartySettings
    {
        public const int ScaleMin = 70, ScaleMax = 150, ScaleStep = 10;
        public const float FrameW = 200, FrameH = 44, BuffH = 16, Header = 12, Gap = 2;
        public const string Pref = "chaos.partyframes";

        public int Scale = 100;
        public bool Locked, Shown = true, ShowSelf, ShowBuffs = true, ShowNumbers = true, Follow = true;

        static int Clamp(int v, int lo, int hi) => Math.Max(lo, Math.Min(hi, v));

        /// <summary>Settings from saved JSON; a missing or odd field takes its default (the main client's sanitize).</summary>
        public static PartySettings Load(string json)
        {
            var s = new PartySettings();
            object o = Json.TryParse(json);
            if (!(o is Dictionary<string, object>)) return s;
            double scale = Json.Number(o, "scale", double.NaN);
            if (!double.IsNaN(scale)) s.Scale = Clamp((int)(Math.Floor(scale / ScaleStep + 0.5) * ScaleStep), ScaleMin, ScaleMax);
            s.Locked = Json.Bool(o, "locked", s.Locked);
            s.Shown = Json.Bool(o, "shown", s.Shown);
            s.ShowSelf = Json.Bool(o, "showSelf", s.ShowSelf);
            s.ShowBuffs = Json.Bool(o, "showBuffs", s.ShowBuffs);
            s.ShowNumbers = Json.Bool(o, "showNumbers", s.ShowNumbers);
            s.Follow = Json.Bool(o, "follow", s.Follow);
            return s;
        }

        public string ToJson() => Json.Serialize(new Dictionary<string, object>
        {
            { "scale", (double)Scale }, { "locked", Locked }, { "shown", Shown }, { "showSelf", ShowSelf }, { "showBuffs", ShowBuffs }, { "showNumbers", ShowNumbers }, { "follow", Follow },
        });

        public void StepScale(int dir) => Scale = Clamp(Scale + dir * ScaleStep, ScaleMin, ScaleMax);

        public float Scaled(float px) => (float)Math.Floor(px * Clamp(Scale, ScaleMin, ScaleMax) / 100f + 0.5f);

        /// <summary>The members to draw: all, or without the viewer when ShowSelf is off.</summary>
        public List<PartyMember> Visible(IEnumerable<PartyMember> members)
        {
            var o = new List<PartyMember>();
            foreach (var m in members) if (ShowSelf || !m.Self) o.Add(m);
            return o;
        }

        public bool BuffsShown(PartyMember m) => ShowBuffs && !m.Far && m.Buffs.Count > 0;

        public float FrameHeight(PartyMember m) => Scaled(FrameH + (BuffsShown(m) ? BuffH : 0));

        /// <summary>A short label for a buff icon (the icon art is not in this client): its name's initials, or the icon key's last letters.</summary>
        public static string BuffLabel(PartyBuff b)
        {
            string n = b.Name ?? "";
            var sb = new System.Text.StringBuilder();
            foreach (string w in n.Split(new[] { ' ', '-', '_' }, StringSplitOptions.RemoveEmptyEntries))
            {
                sb.Append(char.ToUpperInvariant(w[0]));
                if (sb.Length == 2) break;
            }
            if (sb.Length == 0 && !string.IsNullOrEmpty(b.Icon)) sb.Append(char.ToUpperInvariant(b.Icon[0]));
            return sb.ToString();
        }

        /// <summary>Seconds left of a buff for its tooltip (-1 for a buff with no end).</summary>
        public static int SecondsLeft(PartyBuff b, double nowMs) => b.EndsAt <= 0 ? -1 : (int)Math.Max(0, Math.Ceiling((b.EndsAt - nowMs) / 1000.0));
    }
}
