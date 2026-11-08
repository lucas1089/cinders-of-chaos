// Loot labels over the items lying on the ground. A port of game_groundlabels/groundlabelslogic.lua (the rules) and of the scan and the asking
// of groundlabels.lua. Server: data/scripts/chaos/groundloot.lua. The client sees the items on the tiles around it but not their names,
// categories or decay; it asks for the tiles whose items changed and draws a label per item in the rarity colour, following the loot filter.
//
// Extended opcode 230 (JSON {action, data}):
//   client -> server  look {t = [[x, y, z], ...]}      up to 30 tiles, same floor, within 8 x 6 squares
//   server -> client  tiles {t = [{p = [x, y, z], i = [item | corpse]}]}   every asked tile is answered (i may be [])
//                       item   {s (stack index), id, c, nm, r, u, o, pw, g, t, il, e}
//                       corpse {s, id, k = 1, n (items in it), i = [{c, nm, r, u, o, pw, g, t}], e}     (e: seconds until it decays)
// Not ported: the tooltips (tip), picking an item up from its label (raise), the label accent cosmetic. A click on a corpse label opens
// the corpse (Unity side). Tests: Core.Tests/HelperTests.cs (mirrors groundlabels_test.lua).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class GroundLabelSettings
    {
        public bool Enabled = true, RarePlus = true, AltAll = true, Corpses = true, Timers = true;
        public string Size = "normal";   // small | normal | large

        public Dictionary<string, object> ToDict() =>
            new Dictionary<string, object> { { "enabled", Enabled }, { "rarePlus", RarePlus }, { "altAll", AltAll }, { "corpses", Corpses }, { "timers", Timers }, { "size", Size } };

        public static GroundLabelSettings From(object t)
        {
            var o = new GroundLabelSettings();
            if (!(t is Dictionary<string, object>)) return o;
            o.Enabled = Json.Bool(t, "enabled", true); o.RarePlus = Json.Bool(t, "rarePlus", true); o.AltAll = Json.Bool(t, "altAll", true);
            o.Corpses = Json.Bool(t, "corpses", true); o.Timers = Json.Bool(t, "timers", true);
            string size = Json.Text(t, "size", "normal");
            o.Size = size == "small" || size == "large" ? size : "normal";
            return o;
        }
    }

    /// <summary>A row of a tile: an item or a corpse as the server sent it.</summary>
    public sealed class GroundRow
    {
        public LootInfo Info;
        public bool Corpse;
        public int Items;                 // a corpse: how many items it holds
        public int Expire = -1;           // seconds until it decays when received, -1: it does not decay
        public double At;                 // when the row came, in the model's clock (seconds)
        public readonly List<LootInfo> Inside = new List<LootInfo>();
    }

    public sealed class GroundDecision
    {
        public bool Corpse, Dim, Highlight;
        public int Matches;
        public LootInfo Best;
        public bool HasBest;
    }

    /// <summary>A label ready to draw: the text, its colours, the tile it belongs to.</summary>
    public sealed class GroundLabel
    {
        public Pos Tile;
        public GroundRow Row;
        public GroundDecision Decision;
        public string Text = "", Color = "", Border = "", Background = "";
        public double Prio, Dist;
        public int Order;
        public bool Timer;
    }

    public static class GroundLabelRules
    {
        public const int MaxLabels = 40, Rare = 3;
        public const string TextColor = "#d8cfbf", DimColor = "#8c8478", HighlightBackground = "#100c0ef0", PlainBackground = "#0c0a0cd8";
        public const double VerifyMs = 1000;
        public const int ServerRangeX = 8, ServerRangeY = 6, MaxAsk = 30;
        public const double RetrySeconds = 3, ScanMs = 400, MoveScanMs = 60;
        public static readonly string[] SizeOrder = { "small", "normal", "large" };

        /// <summary>The things the labels are about: not ground, border or bottom items; a corpse (a container that is not picked up), or a pickupable item that is not on top.</summary>
        public static bool IsCandidate(bool ground, bool border, bool bottom, bool top, bool pickupable, bool container, bool corpse)
        {
            if (ground || border || bottom) return false;
            if (container && corpse) return true;
            return pickupable && !top;
        }

        public static bool IsCandidate(Item it)
        {
            var t = it.Type;
            if (t == null) return false;
            // a corpse is a container that cannot be picked up (the server decides which of them is one)
            return IsCandidate(t.Ground, t.GroundBorder, t.OnBottom, t.OnTop, t.Pickupable, t.Container, t.Container && !t.Pickupable);
        }

        /// <summary>The tile's candidate items as a string; the server is asked again when it changes.</summary>
        public static string Signature(Tile tile)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var th in tile.Things)
            {
                if (th.IsCreature || !IsCandidate(th.Item)) continue;
                if (sb.Length > 0) sb.Append(';');
                sb.Append(th.Item.Id).Append('x').Append(Math.Max(1, th.Item.Count));
            }
            return sb.ToString();
        }

        public static bool IsRarePlus(LootInfo i) => i.U || i.O || i.Pw || i.R >= Rare;

        static string FilterState(LootInfo info, LootFilterSettings filter)
        {
            if (info.Pw) return "highlight";   // a legendary power always glows (as on the server)
            return LootFilterRules.Classify(info, filter);
        }

        /// <summary>Items of a corpse the label counts: the ones the filter makes glow, and Rare+ ones the filter does not hide. Best: the highest rank.</summary>
        static int CorpseMatches(GroundRow row, GroundLabelSettings s, LootFilterSettings filter, out LootInfo best, out bool hasBest)
        {
            int n = 0, bestRank = -1;
            best = default(LootInfo); hasBest = false;
            foreach (var info in row.Inside)
            {
                string st = FilterState(info, filter);
                if (st == "highlight" || (s.RarePlus && st != "dim" && IsRarePlus(info)))
                {
                    n++;
                    int rank = info.U ? 100 : info.R;
                    if (rank > bestRank) { best = info; hasBest = true; bestRank = rank; }
                }
            }
            return n;
        }

        /// <summary>Whether a row gets a label, and how. Null: no label. alt: Alt is held (every item, the dimmed ones too).</summary>
        public static GroundDecision Decide(GroundRow row, GroundLabelSettings s, LootFilterSettings filter, bool alt)
        {
            if (!s.Enabled || row == null) return null;
            bool showAll = alt && s.AltAll;
            if (row.Corpse)
            {
                if (!s.Corpses) return null;
                LootInfo best; bool hasBest;
                int n = CorpseMatches(row, s, filter, out best, out hasBest);
                if (n > 0) return new GroundDecision { Corpse = true, Matches = n, Best = best, HasBest = hasBest, Highlight = true };
                if (showAll && row.Items > 0) return new GroundDecision { Corpse = true, Dim = true };
                return null;
            }
            string st = FilterState(row.Info, filter);
            if (st == "highlight") return new GroundDecision { Highlight = true };
            if (st != "dim" && s.RarePlus && IsRarePlus(row.Info)) return new GroundDecision();
            if (showAll) return new GroundDecision { Dim = st == "dim" };
            return null;
        }

        public static string TitleCase(string name)
        {
            name = string.IsNullOrEmpty(name) ? "item" : name;
            var sb = new System.Text.StringBuilder();
            bool start = true;
            foreach (char c in name)
            {
                if (char.IsLetter(c)) { sb.Append(start ? char.ToUpperInvariant(c) : c); start = false; }
                else { sb.Append(c); if (c != '\'' && !char.IsDigit(c)) start = true; }
            }
            return sb.ToString();
        }

        /// <summary>Seconds to "1:42", "0:07", "1:02:03".</summary>
        public static string TimerText(double sec)
        {
            long s = (long)Math.Max(0, Math.Floor(sec));
            long h = s / 3600, m = s / 60 % 60, r = s % 60;
            return h > 0 ? string.Format("{0}:{1:00}:{2:00}", h, m, r) : string.Format("{0}:{1:00}", m, r);
        }

        /// <summary>Seconds left of a row at time `now` (the row's expiry counted from the time it came), -1 when it does not decay.</summary>
        public static double SecondsLeft(GroundRow row, double now) => row.Expire < 0 ? -1 : Math.Max(0, row.Expire - (now - row.At));

        /// <summary>The timer is shown for what is worth it: corpses with loot, items that glow or are Rare+.</summary>
        public static bool ShowTimer(GroundRow row, GroundDecision d, GroundLabelSettings s) => s.Timers && row.Expire >= 0 && (d.Corpse || d.Highlight || IsRarePlus(row.Info));

        public static string ItemText(GroundRow row)
        {
            int count = row.Info.C;
            string name = TitleCase(row.Info.Nm);
            string r = !row.Info.U ? LootFilterRules.RarityName(row.Info.R) : null;
            return (count > 1 ? count + "x " : "") + (r != null ? r + " " : "") + name;
        }

        public static string CorpseText(GroundRow row, GroundDecision d)
        {
            int n = d.Matches > 0 ? d.Matches : row.Items;
            return Loc.T(n == 1 ? "Corpse: {0} item" : "Corpse: {0} items", n);
        }

        public static string Text(GroundRow row, GroundDecision d, GroundLabelSettings s, double now)
        {
            string text = d.Corpse ? CorpseText(row, d) : ItemText(row);
            if (ShowTimer(row, d, s)) text += "  " + TimerText(SecondsLeft(row, now));
            return text;
        }

        public static string Color(GroundRow row, GroundDecision d)
        {
            if (d.Dim) return DimColor;
            if (d.Corpse) return d.HasBest ? LootFilterRules.Color(d.Best) ?? TextColor : TextColor;
            return LootFilterRules.Color(row.Info) ?? TextColor;
        }

        /// <summary>The text, border and background of a label.</summary>
        public static void Style(GroundDecision d, string color, out string text, out string border, out string background)
        {
            text = color;
            if (d.Highlight) { border = color; background = HighlightBackground; }
            else { border = "#3a3230"; background = PlainBackground; }
        }

        /// <summary>Higher first: uniques, then rarity, highlighted before plain, corpses with loot, then the nearest.</summary>
        public static double Priority(GroundRow row, GroundDecision d)
        {
            double p;
            if (d.Corpse) p = 300 + (d.HasBest ? (d.Best.U ? 100 : d.Best.R * 5) : 0);
            else
            {
                p = (row.Info.U ? 600 : 0) + row.Info.R * 20 + (row.Info.O ? 40 : 0);
                if (d.Highlight) p += 200;
            }
            if (d.Dim) p -= 1000;
            return p;
        }

        /// <summary>Keeps the best `max` labels (priority, then nearest, then order), best first.</summary>
        public static List<GroundLabel> Select(List<GroundLabel> entries, int max = MaxLabels)
        {
            entries.Sort((a, b) =>
            {
                if (a.Prio != b.Prio) return b.Prio.CompareTo(a.Prio);
                if (a.Dist != b.Dist) return a.Dist.CompareTo(b.Dist);
                return a.Order.CompareTo(b.Order);
            });
            if (entries.Count > max) entries.RemoveRange(max, entries.Count - max);
            return entries;
        }

        // ------------------------------------------------------------------------------------ layout
        public struct LayoutBlock { public int Key; public float Ax, Ay, W, H; }
        public struct LayoutBox { public float X, Y, W, H; }

        static bool Overlaps(LayoutBox a, float x, float y, float w, float h, float gap) =>
            x < a.X + a.W + gap && a.X < x + w + gap && y < a.Y + a.H + gap && a.Y < y + h + gap;

        static bool FirstHit(List<LayoutBox> placed, float x, float y, float w, float h, float gap, out LayoutBox hit)
        {
            foreach (var a in placed) if (Overlaps(a, x, y, w, h, gap)) { hit = a; return true; }
            hit = default(LayoutBox);
            return false;
        }

        /// <summary>One block of labels per tile, anchored at the tile (ax, ay in pixels, any origin; y grows down). Each block wants to sit centred
        /// over its anchor, its bottom `lift` pixels above it; a block that would overlap one placed before moves up past it (then, if that is more
        /// than maxShift, down instead). Returns each block's top-left relative to its anchor, by key.</summary>
        public static Dictionary<int, LayoutBox> Layout(IList<LayoutBlock> groups, float gap = 2, float lift = 0, float maxShift = 200)
        {
            var placed = new List<LayoutBox>();
            var o = new Dictionary<int, LayoutBox>();
            foreach (var g in groups)
            {
                float x = g.Ax - (float)Math.Floor(g.W / 2);
                float want = g.Ay - lift - g.H;
                float y = want;
                LayoutBox hit;
                bool bumped;
                int n = 0;
                do
                {
                    bumped = FirstHit(placed, x, y, g.W, g.H, gap, out hit);
                    if (bumped) y = hit.Y - gap - g.H;
                    n++;
                } while (bumped && n <= 64 && want - y <= maxShift);
                if (bumped || want - y > maxShift)
                {
                    float down = want;
                    n = 0;
                    do
                    {
                        bumped = FirstHit(placed, x, down, g.W, g.H, gap, out hit);
                        if (bumped) down = hit.Y + hit.H + gap;
                        n++;
                    } while (bumped && n <= 64 && down - want <= maxShift);
                    y = (!bumped && down - want <= maxShift) ? down : want;
                }
                placed.Add(new LayoutBox { X = x, Y = y, W = g.W, H = g.H });
                o[g.Key] = new LayoutBox { X = x - g.Ax, Y = y - g.Ay, W = g.W, H = g.H };
            }
            return o;
        }
    }

    /// <summary>The scan and the asking: which tiles around the player hold things worth a label, what the server said about them.</summary>
    public sealed class GroundLabelsModel
    {
        public const byte Opcode = 230;

        sealed class TileState
        {
            public string Sig = "", AskedSig;
            public double AskedAt = -1e9;
            public List<GroundRow> Rows;
        }

        readonly ExtOpcodes ext;
        public Func<double> Clock = () => 0;   // seconds
        public GroundLabelSettings Settings = new GroundLabelSettings();
        readonly Dictionary<Pos, TileState> tiles = new Dictionary<Pos, TileState>();
        /// <summary>The rows or the tiles changed: the labels need laying out again.</summary>
        public bool Dirty;
        public int Asked, Answered;

        public GroundLabelsModel(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        public int TileCount => tiles.Count;

        public IEnumerable<KeyValuePair<Pos, List<GroundRow>>> Known()
        {
            foreach (var kv in tiles) if (kv.Value.Rows != null) yield return new KeyValuePair<Pos, List<GroundRow>>(kv.Key, kv.Value.Rows);
        }

        /// <summary>Looks at the tiles round the player (the server's range 8 x 6, or less when the view is smaller) and asks for the ones whose items changed.
        /// Returns the number of tiles asked.</summary>
        public int Scan(World w, Pos center, int rx = GroundLabelRules.ServerRangeX, int ry = GroundLabelRules.ServerRangeY)
        {
            rx = Math.Min(rx, GroundLabelRules.ServerRangeX); ry = Math.Min(ry, GroundLabelRules.ServerRangeY);
            double now = Clock();
            var seen = new HashSet<Pos>();
            var need = new List<Pos>();
            if (!Settings.Enabled) { if (tiles.Count > 0) { tiles.Clear(); Dirty = true; } return 0; }
            for (int dy = -ry; dy <= ry; dy++)
                for (int dx = -rx; dx <= rx; dx++)
                {
                    var p = new Pos(center.X + dx, center.Y + dy, center.Z);
                    var tile = w.Get(p);
                    if (tile == null || tile.Things.Count <= 1) continue;
                    string sig = GroundLabelRules.Signature(tile);
                    if (sig.Length == 0) continue;
                    seen.Add(p);
                    TileState t;
                    if (!tiles.TryGetValue(p, out t)) { t = new TileState(); tiles[p] = t; }
                    if (t.Sig != sig)
                    {
                        t.Sig = sig;
                        if (t.Rows != null) { t.Rows = null; Dirty = true; }
                    }
                    if (t.Rows == null && (t.AskedSig != sig || now - t.AskedAt >= GroundLabelRules.RetrySeconds)) need.Add(p);
                }
            var gone = new List<Pos>();
            foreach (var p in tiles.Keys) if (!seen.Contains(p)) gone.Add(p);
            foreach (var p in gone) { tiles.Remove(p); Dirty = true; }
            int sent = 0;
            for (int i = 0; i < need.Count; i += GroundLabelRules.MaxAsk)
            {
                var batch = new List<object>();
                for (int j = i; j < need.Count && j < i + GroundLabelRules.MaxAsk; j++)
                {
                    var t = tiles[need[j]];
                    t.AskedSig = t.Sig; t.AskedAt = now;
                    batch.Add(new List<object> { need[j].X, need[j].Y, need[j].Z });
                    sent++;
                }
                ext.Send(Opcode, "look", new Dictionary<string, object> { { "t", batch } });
            }
            Asked += sent;
            return sent;
        }

        static LootInfo InfoOf(object o)
        {
            var i = LootInfo.From(o);
            return i;
        }

        void OnMessage(ExtMessage m)
        {
            if (m.Action != "tiles") return;
            double now = Clock();
            foreach (object entry in Json.List(m.Data, "t"))
            {
                var p = Json.List(entry, "p");
                if (p.Count < 3 || !(p[0] is double) || !(p[1] is double) || !(p[2] is double)) continue;
                var pos = new Pos((int)(double)p[0], (int)(double)p[1], (int)(double)p[2]);
                TileState t;
                // an answer for a tile that changed again in between is dropped: the newer question is on its way
                if (!tiles.TryGetValue(pos, out t) || t.AskedSig != t.Sig) continue;
                var rows = new List<GroundRow>();
                foreach (object r in Json.List(entry, "i"))
                {
                    if (!(r is Dictionary<string, object>)) continue;
                    var row = new GroundRow { At = now, Expire = Json.Get(r, "e") is double e ? (int)e : -1 };
                    if (Json.Get(r, "k") is double k && k == 1 || Json.Get(r, "k") is bool kb && kb)
                    {
                        row.Corpse = true;
                        row.Items = Json.Int(r, "n");
                        row.Info = InfoOf(r);
                        foreach (object inside in Json.List(r, "i")) row.Inside.Add(InfoOf(inside));
                    }
                    else row.Info = InfoOf(r);
                    rows.Add(row);
                }
                t.Rows = rows;
                Dirty = true;
                Answered++;
            }
        }

        /// <summary>The labels to draw now, best first, at most MaxLabels. dist: tiles from the player.</summary>
        public List<GroundLabel> Labels(Pos player, LootFilterSettings filter, bool alt)
        {
            double now = Clock();
            var entries = new List<GroundLabel>();
            int order = 0;
            foreach (var kv in tiles)
            {
                if (kv.Value.Rows == null) continue;
                foreach (var row in kv.Value.Rows)
                {
                    var d = GroundLabelRules.Decide(row, Settings, filter, alt);
                    if (d == null) continue;
                    var l = new GroundLabel { Tile = kv.Key, Row = row, Decision = d, Prio = GroundLabelRules.Priority(row, d), Order = ++order,
                        Dist = Math.Max(Math.Abs(kv.Key.X - player.X), Math.Abs(kv.Key.Y - player.Y)), Timer = GroundLabelRules.ShowTimer(row, d, Settings) };
                    l.Text = GroundLabelRules.Text(row, d, Settings, now);
                    GroundLabelRules.Style(d, GroundLabelRules.Color(row, d), out l.Color, out l.Border, out l.Background);
                    entries.Add(l);
                }
            }
            return GroundLabelRules.Select(entries);
        }

        public void Reset() { tiles.Clear(); Dirty = true; Asked = Answered = 0; }
    }
}
