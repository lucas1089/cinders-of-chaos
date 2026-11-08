// Phase 8, track A: the card layout of the item tooltip (game_itemtooltip tooltiplogic.lua L.card and item_tooltip.lua): head (name, kind, item level, flags), stat tiles
// and one line of the other base stats, modifier groups with tier tags and ranges, extra groups (sockets, set, notes, passive, charges), requirement chips with the
// sources and weight in the foot. TipCard.Build is pure (no sizes); TipCardLayout turns it into boxes with a measure function the Unity side supplies.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Chaos.Core
{
    public sealed class TipTile { public string Key = "", Caption = "", Value = ""; public bool Hero; }

    public sealed class TipRow
    {
        public bool IsMod;
        public string Tag = "", TagColor = "", Text = "", Color = "", Range = "";
        public bool Top;
        /// <summary>Text and colour pairs when the row has more than one colour ("name" gold, " [bound]").</summary>
        public string[] Parts;
    }

    public sealed class TipGroup
    {
        public string Caption = "", CapColor = "";
        public readonly List<TipRow> Rows = new List<TipRow>();
    }

    public sealed class TipChip { public string Text = "", Color = ""; public bool Low; }

    public sealed class TipCard
    {
        public string Title = "", TitleColor = "", Kind = "", KindColor = "", SlotLine = "", Level = "";
        public readonly List<TipLine> Flags = new List<TipLine>();
        public readonly List<TipTile> Tiles = new List<TipTile>();
        public readonly List<string[]> ExtraLines = new List<string[]>();
        public string Effect = "", EffectColor = "";
        public readonly List<TipGroup> Mods = new List<TipGroup>();
        public readonly List<TipGroup> Extras = new List<TipGroup>();
        public readonly List<TipChip> Chips = new List<TipChip>();
        public string FitCaption = "";
        public readonly List<TipChip> FitChips = new List<TipChip>();
        public readonly List<TipLine> Foot = new List<TipLine>();
        public bool Comparable;
        public bool HasStats => Tiles.Count > 0 || ExtraLines.Count > 0 || Effect.Length > 0;

        public const string Sep = " - ";
        public const int TileMax = 4, ExtraLine = 44, FootLine = 50;
        public static readonly string[] TileOrder = { "dps", "attack", "speed", "range", "armor", "defense", "extradefense", "hitchance" };
        static readonly HashSet<string> Unsigned = new HashSet<string> { "attack", "defense", "extradefense", "armor", "range", "hitchance", "attackspeed", "yourinterval", "dps" };
        static readonly Regex SupportRx = new Regex(@"^A support rune for a spell socket: (.*?)\.\s+Fits (.*?) spells\.(.*)$", RegexOptions.Singleline | RegexOptions.CultureInvariant);

        public static string Caps(string s) => (s ?? "").ToUpperInvariant();

        static string TileCaption(string key)
        {
            switch (key)
            {
                case "dps": return Loc.T("DPS");
                case "attack": return Loc.T("Attack");
                case "speed": return Loc.T("Speed");
                case "range": return Loc.T("Range");
                case "armor": return Loc.T("Armour");
                case "defense": return Loc.T("Defense");
                case "extradefense": return Loc.T("Extra Defense");
                case "hitchance": return Loc.T("Hit Chance");
                default: return key;
            }
        }

        /// <summary>The base rows split into tiles (at most four, DPS the hero) and the rest as label and value lines (tooltiplogic.lua L.statTiles).</summary>
        public static void StatTiles(object baseRows, List<TipTile> tiles, List<KeyValuePair<string, string>> rest)
        {
            var byKey = new Dictionary<string, object>();
            var list = Json.List(baseRows == null ? null : new Dictionary<string, object> { { "b", baseRows } }, "b");
            foreach (object b in list) { string k = Json.Text(b, "k"); if (k.Length > 0 && !byKey.ContainsKey(k)) byKey[k] = b; }
            object speed = byKey.ContainsKey("yourinterval") ? byKey["yourinterval"] : byKey.ContainsKey("attackspeed") ? byKey["attackspeed"] : null;
            var used = new HashSet<object>();
            foreach (string key in TileOrder)
            {
                object b = key == "speed" ? speed : (byKey.ContainsKey(key) ? byKey[key] : null);
                if (b == null || tiles.Count >= TileMax) continue;
                tiles.Add(new TipTile { Key = key, Caption = TileCaption(key), Value = TipLines.BaseValue(b, false), Hero = key == "dps" });
                used.Add(b);
            }
            foreach (object b in list)
            {
                if (used.Contains(b)) continue;
                bool imp = Json.Bool(b, "imp");
                string k = Json.Text(b, "k");
                bool signed = imp || !Unsigned.Contains(k);
                string label = Json.Text(b, "l");
                if (label.Length == 0) label = k.Length > 0 ? k : "?";
                rest.Add(new KeyValuePair<string, string>(label, TipLines.BaseValue(b, signed)));
            }
        }

        /// <summary>The rest of the base rows as centred lines of text and colour pairs, at most ExtraLine characters each (L.extraLines).</summary>
        public static List<string[]> ExtraLines2(List<KeyValuePair<string, string>> rest)
        {
            var lines = new List<string[]>();
            var parts = new List<string>();
            int len = 0;
            foreach (var r in rest)
            {
                string label = r.Key + " ", value = r.Value;
                int need = label.Length + value.Length + (len > 0 ? Sep.Length : 0);
                if (len > 0 && len + need > ExtraLine)
                {
                    lines.Add(parts.ToArray());
                    parts = new List<string>(); len = 0; need = label.Length + value.Length;
                }
                if (len > 0) { parts.Add(Sep); parts.Add(TipLines.Dim); }
                parts.Add(label); parts.Add(TipLines.Text);
                parts.Add(value); parts.Add(TipLines.Quality);
                len += need;
            }
            if (parts.Count > 0) lines.Add(parts.ToArray());
            return lines;
        }

        static string RangeText(object m)
        {
            if (Json.Get(m, "lo") == null || Json.Get(m, "hi") == null) return "";
            double lo = Json.Number(m, "lo"), hi = Json.Number(m, "hi");
            return lo == hi ? TipLines.Trim(lo) : TipLines.Trim(lo) + "-" + TipLines.Trim(hi);
        }

        /// <summary>The modifier groups: prefixes, suffixes, the corrupted implicit, then the veiled slot (L.modGroups).</summary>
        public static List<TipGroup> ModGroups(object tip)
        {
            var groups = new List<TipGroup>();
            TipGroup group = null;
            string side = null;
            object sides = Json.Get(tip, "sides");
            foreach (object m in Json.List(tip, "mods"))
            {
                string sd = Json.Text(m, "sd");
                if (group == null || sd != side)
                {
                    side = sd;
                    string caption = "";
                    if (sd == "i") caption = Caps(Loc.T("Corrupted implicit"));
                    else if (sd.Length > 0)
                    {
                        string head = Caps(sd == "p" ? Loc.T("Prefixes") : Loc.T("Suffixes"));
                        if (sides is Dictionary<string, object> && Json.Get(sides, "max") != null)
                        {
                            double limit = Json.Get(sides, sd == "p" ? "mp" : "ms") != null ? Json.Number(sides, sd == "p" ? "mp" : "ms") : Json.Number(sides, "max");
                            head = head + " " + (int)Json.Number(sides, sd == "p" ? "p" : "s") + "/" + (int)limit;
                        }
                        caption = head;
                    }
                    group = new TipGroup { Caption = caption };
                    groups.Add(group);
                }
                string g = Json.Text(m, "g");
                string color = sd == "i" ? TipLines.Corrupted : Json.Bool(m, "pw") ? TipLines.Power : g == "chaos" ? TipLines.Chaos : g == "element" ? TipLines.Element : TipLines.Mod;
                var row = new TipRow { IsMod = true, Text = Json.Text(m, "t"), Color = color, Range = RangeText(m) };
                if (Json.Get(m, "tr") != null)
                {
                    int tr = (int)Json.Number(m, "tr");
                    row.Tag = "T" + tr;
                    row.TagColor = TipLines.TierColor(tr);
                    row.Top = Json.Get(tip, "maxTier") != null && tr == (int)Json.Number(tip, "maxTier");
                }
                if (Json.Bool(m, "bd")) row.Parts = new[] { row.Text, color, " " + Loc.T("[bound]"), TipLines.Bound };
                group.Rows.Add(row);
            }
            object veil = Json.Get(tip, "veil");
            if (veil is Dictionary<string, object>)
            {
                string s = Json.Text(veil, "s");
                if (s == "veiled")
                {
                    var g = new TipGroup { Caption = Caps(Loc.T("Veiled modifier")), CapColor = TipLines.Veiled };
                    g.Rows.Add(new TipRow { Text = Loc.T("Reveal it with an Orb of Unveiling"), Color = TipLines.Dim });
                    groups.Add(g);
                }
                else if (s == "open")
                {
                    var g = new TipGroup { Caption = Caps(Loc.T("Veiled")), CapColor = TipLines.Veiled };
                    int tr = (int)Json.Number(veil, "tr", 1);
                    g.Rows.Add(new TipRow
                    {
                        IsMod = true, Tag = Json.Text(veil, "tn", "V" + tr), TagColor = tr >= 1 && tr <= TipLines.VeilTierColors.Length ? TipLines.VeilTierColors[tr - 1] : TipLines.Veiled,
                        Text = Json.Text(veil, "n", "?"), Color = TipLines.Veiled, Range = RangeText(veil),
                    });
                    foreach (string line in TipLines.WrapText(Json.Text(veil, "t"), TipLines.Wrap)) g.Rows.Add(new TipRow { Text = line, Color = TipLines.VeiledText });
                    groups.Add(g);
                }
            }
            return groups;
        }

        static void TextRows(TipGroup g, IEnumerable<string> lines, string color)
        {
            foreach (string line in lines) g.Rows.Add(new TipRow { Text = line, Color = color });
        }

        /// <summary>Sockets, the set, the note, the flavour, a unique's passive, then locked, appearance, store, charges (L.extraGroups).</summary>
        public static List<TipGroup> ExtraGroups(object tip)
        {
            var groups = new List<TipGroup>();
            Action<TipGroup> add = g => { if (g.Rows.Count > 0 || g.Caption.Length > 0) groups.Add(g); };
            object sockets = Json.Get(tip, "sockets");
            if (sockets is Dictionary<string, object> && Json.Number(sockets, "count") > 0)
            {
                int count = (int)Json.Number(sockets, "count"), filled = 0;
                var list = Json.List(sockets, "list");
                var g = new TipGroup { CapColor = TipLines.Gold };
                for (int i = 0; i < count; i++)
                {
                    object gem = i < list.Count ? list[i] : null;
                    string name = Json.Text(gem, "name");
                    if (name.Length > 0)
                    {
                        filled++;
                        string text = Json.Text(gem, "text");
                        string extra = text.Length > 0 ? ": " + text : "";
                        string col = Json.Text(gem, "color", TipLines.Gem);
                        g.Rows.Add(new TipRow { Text = name + extra, Color = col, Parts = new[] { name, col, extra, TipLines.Gem } });
                    }
                    else g.Rows.Add(new TipRow { Text = Loc.T("empty socket"), Color = TipLines.Empty });
                }
                g.Caption = Caps(Loc.T("Sockets {0}/{1}", filled, count));
                add(g);
            }
            object unq = Json.Get(tip, "unique");
            object set = unq is Dictionary<string, object> && Json.Get(unq, "set") is Dictionary<string, object> ? Json.Get(unq, "set") : Json.Get(tip, "set");
            if (set is Dictionary<string, object>)
            {
                var o = new TipLines.Out();
                TipLines.SetLines(o, set);
                if (o.Lines.Count > 0)
                {
                    var g = new TipGroup { Caption = o.Lines[0].Text, CapColor = TipLines.SetC };
                    for (int i = 1; i < o.Lines.Count; i++) g.Rows.Add(new TipRow { Text = o.Lines[i].Text.TrimStart(), Color = o.Lines[i].Color });
                    add(g);
                }
            }
            if (Json.Text(tip, "note").Length > 0) { var g = new TipGroup(); TextRows(g, TipLines.WrapText(Json.Text(tip, "note"), TipLines.Wrap), TipLines.Gold); add(g); }
            object passive = Json.Get(tip, "passive");
            bool hasPassive = passive is Dictionary<string, object> && Json.Get(passive, "name") != null && Json.Get(passive, "text") != null;
            string desc = hasPassive ? Json.Text(passive, "flavor") : Json.Text(tip, "desc");
            if (desc.Length > 0 && Support(desc) == null) { var g = new TipGroup(); TextRows(g, TipLines.WrapText(desc, TipLines.Wrap), TipLines.Dim); add(g); }
            if (hasPassive)
            {
                var g = new TipGroup { Caption = Json.Text(passive, "name"), CapColor = TipLines.PassiveC };
                TextRows(g, TipLines.WrapText(Json.Text(passive, "text"), TipLines.Wrap), TipLines.PassiveText);
                add(g);
            }
            var misc = new TipGroup();
            if (Json.Bool(tip, "locked")) misc.Rows.Add(new TipRow { Text = Loc.T("Locked"), Color = TipLines.Gold });
            object look = Json.Get(tip, "look");
            if (look is Dictionary<string, object> && Json.Text(look, "name").Length > 0) misc.Rows.Add(new TipRow { Text = Loc.T("Appearance: {0}", Json.Text(look, "name")), Color = TipLines.Mod });
            if (Json.Text(tip, "store").Length > 0) misc.Rows.Add(new TipRow { Text = Json.Text(tip, "store"), Color = TipLines.Gold });
            if (Json.Text(tip, "collects").Length > 0) TextRows(misc, TipLines.WrapText(Json.Text(tip, "collects"), TipLines.Wrap), TipLines.Dim);
            string charges = TipLines.ChargesText(Json.Get(tip, "charges"));
            if (charges != null) misc.Rows.Add(new TipRow { Text = charges, Color = TipLines.Text });
            add(misc);
            return groups;
        }

        /// <summary>The requirement chips: level (red while the player is below it), magic level, one per class (L.reqChips).</summary>
        public static List<TipChip> ReqChips(object req, int playerLevel)
        {
            var chips = new List<TipChip>();
            if (!(req is Dictionary<string, object>)) return chips;
            if (Json.Get(req, "level") != null)
            {
                int need = (int)Json.Number(req, "level");
                bool low = playerLevel < need;
                chips.Add(new TipChip { Text = Loc.T("Level {0}", need), Color = low ? TipLines.Red : TipLines.Text, Low = low });
            }
            if (Json.Get(req, "magic") != null) chips.Add(new TipChip { Text = Loc.T("Magic level {0}", (int)Json.Number(req, "magic")), Color = TipLines.Text });
            string voc = Json.Text(req, "voc");
            if (voc.Length > 0)
                foreach (string name in voc.Split(','))
                {
                    string n = name.Trim();
                    if (n.Length > 0) chips.Add(new TipChip { Text = n, Color = TipLines.Text });
                }
            return chips;
        }

        /// <summary>A spell support rune's description: {effect, fits, combine, command}; null for any other text (L.supportInfo).</summary>
        public sealed class SupportRune { public string Effect = ""; public readonly List<string> Fits = new List<string>(); public bool Combine, Command; }

        public static SupportRune Support(string desc)
        {
            if (string.IsNullOrEmpty(desc)) return null;
            var m = SupportRx.Match(desc);
            if (!m.Success) return null;
            var r = new SupportRune { Effect = TipLines.Title(m.Groups[1].Value), Combine = m.Groups[3].Value.Contains("combine"), Command = m.Groups[3].Value.Contains("!supports") };
            foreach (string k in m.Groups[2].Value.Split(',')) { string t = k.Trim(); if (t.Length > 0) r.Fits.Add(t); }
            return r;
        }

        /// <summary>Compare only wearable gear: the server marks it (cmp slots) and it has numbers to compare (L.comparable).</summary>
        public static bool IsComparable(object tip) => ItemCompare.Comparable(tip);

        /// <summary>The foot: hint lines, the sources lines and the weight; the weight joins the last dim line when it fits (L.footLines).</summary>
        public static List<TipLine> FootLines(object tip, List<string> hints)
        {
            var rows = new List<TipLine>();
            if (hints != null) foreach (string h in hints) rows.Add(new TipLine { Text = h, Color = TipLines.Dim });
            rows.AddRange(TipLines.SourceLines(Json.Get(tip, "src")));
            if (Json.Get(tip, "weight") != null)
            {
                string w = Loc.T("Weight {0} oz", TipLines.Trim(Json.Number(tip, "weight")));
                var last = rows.Count > 0 ? rows[rows.Count - 1] : null;
                if (last != null && last.Color == TipLines.Dim && last.Text.Length + Sep.Length + w.Length <= FootLine) last.Text = last.Text + Sep + w;
                else rows.Add(new TipLine { Text = w, Color = TipLines.Dim });
            }
            return rows;
        }

        /// <summary>The whole card of a tip. playerLevel: the character's level.</summary>
        public static TipCard Build(object tip, int playerLevel)
        {
            var c = new TipCard();
            if (tip == null) return c;
            c.Title = TipLines.Title(Json.Text(tip, "name"));
            c.TitleColor = TipLines.TitleColor(tip);
            string kindText = TipLines.KindText(tip, out string slotLine);
            c.Kind = kindText != null ? Caps(kindText) : "";
            if (Support(Json.Text(tip, "desc")) != null) c.Kind = Caps((kindText != null ? kindText + " " : "") + Loc.T("Support rune"));
            c.KindColor = c.TitleColor;
            c.SlotLine = slotLine ?? "";
            if (Json.Get(tip, "level") != null)
                c.Level = Loc.T("Item Level {0}", (int)Json.Number(tip, "level")) + (Json.Get(tip, "maxTier") != null ? Sep + Loc.T("up to T{0}", (int)Json.Number(tip, "maxTier")) : "");
            object quality = Json.Get(tip, "quality");
            if (quality is Dictionary<string, object> && Json.Number(quality, "q") > 0)
                c.Flags.Add(new TipLine { Text = Loc.T("Quality +{0}%  (up to {1}%)", (int)Json.Number(quality, "q"), (int)Json.Number(quality, "cap", 20)), Color = TipLines.Quality });
            if (Json.Bool(tip, "ruined")) c.Flags.Add(new TipLine { Text = Loc.T("Ruined: no orb can change this item"), Color = TipLines.Red });
            if (Json.Bool(tip, "corrupted")) c.Flags.Add(new TipLine { Text = Loc.T("Corrupted: no orb can change this item"), Color = TipLines.Corrupted });
            var rest = new List<KeyValuePair<string, string>>();
            StatTiles(Json.Get(tip, "base"), c.Tiles, rest);
            c.ExtraLines.AddRange(ExtraLines2(rest));
            c.Mods.AddRange(ModGroups(tip));
            c.Extras.AddRange(ExtraGroups(tip));
            c.Chips.AddRange(ReqChips(Json.Get(tip, "req"), playerLevel));
            var rune = Support(Json.Text(tip, "desc"));
            List<string> hints = null;
            if (rune != null)
            {
                c.Effect = rune.Effect; c.EffectColor = TipLines.Gold;
                c.FitCaption = Caps(Loc.T("Fits spells"));
                foreach (string f in rune.Fits) c.FitChips.Add(new TipChip { Text = f, Color = TipLines.Text });
                hints = new List<string>();
                if (rune.Combine) hints.Add(Loc.T("Three combine into one of the next level."));
                if (rune.Command) hints.Add(Loc.T("Open the spell supports with !supports."));
            }
            c.Foot.AddRange(FootLines(tip, hints));
            c.Comparable = IsComparable(tip);
            return c;
        }
    }

    /// <summary>One box of the laid out card: what to draw, where (relative to the card's top left) and in which colour.</summary>
    public sealed class CardBox
    {
        public string Kind = "";   // title, kind, line, flag, sep, tile, effect, extra, caption, row, chip, foot, fitcaption
        public RectD R;
        public string Text = "", Color = "", Caption = "", Tag = "", TagColor = "", Range = "";
        public string[] Parts;
        public bool Hero, Low, Top;
        public int Size;
    }

    public static class TipCardLayout
    {
        public const double Pad = 10, Gap = 6, TileH = 40, HeroTileH = 46, ChipH = 18, ChipGap = 4, ChipPad = 14, LineH = 16, CaptionH = 14, SepH = 7, TitleH = 24;

        /// <summary>Splits chips into rows of at most maxw (tooltiplogic.lua chipRows): widths[i] is the width of chip i; returns lists of chip indices.</summary>
        public static List<List<int>> ChipRows(IList<double> widths, double gap, double maxw)
        {
            var rows = new List<List<int>>();
            var row = new List<int>();
            double x = 0;
            for (int i = 0; i < widths.Count; i++)
            {
                double w = widths[i];
                if (row.Count > 0 && x + gap + w > maxw) { rows.Add(row); row = new List<int>(); x = 0; }
                x += (row.Count > 0 ? gap : 0) + w;
                row.Add(i);
            }
            if (row.Count > 0) rows.Add(row);
            return rows;
        }

        /// <summary>Tile rectangles in a row of the given width: equal tiles with a gap, the hero (DPS) a third wider.</summary>
        public static List<RectD> TileRects(IList<TipTile> tiles, double x, double y, double width)
        {
            var rects = new List<RectD>();
            int n = tiles.Count;
            if (n == 0) return rects;
            double total = width - (n - 1) * Gap;
            double weight = 0;
            foreach (var t in tiles) weight += t.Hero ? 1.33 : 1.0;
            double cx = x;
            foreach (var t in tiles)
            {
                double w = total * (t.Hero ? 1.33 : 1.0) / weight;
                rects.Add(new RectD(cx, y, w, t.Hero ? HeroTileH : TileH));
                cx += w + Gap;
            }
            return rects;
        }

        /// <summary>Lays the card out for a width. measure(text, size, width) is the height of the text wrapped to the width (one line when width is 0) and its width via measureW.</summary>
        public static List<CardBox> Plan(TipCard c, double width, Func<string, int, double> measureW, out double height, IList<TipLine> notes = null)
        {
            var boxes = new List<CardBox>();
            double y = Pad, inner = width - 2 * Pad;
            Action<string, string, string, int, double, bool> line = (kind, text, color, size, h, big) =>
            {
                boxes.Add(new CardBox { Kind = kind, Text = text, Color = color, Size = size, R = new RectD(Pad, y, inner, h) });
                y += h;
            };
            line("title", c.Title, c.TitleColor, 16, TitleH, true);
            if (c.Kind.Length > 0) line("kind", c.Kind, c.KindColor, 10, 13, false);
            if (c.SlotLine.Length > 0) line("line", c.SlotLine, TipLines.Dim, 11, LineH, false);
            if (c.Level.Length > 0) line("line", c.Level, TipLines.Dim, 11, LineH, false);
            foreach (var f in c.Flags) line("flag", f.Text, f.Color, 11, LineH, false);
            if (c.HasStats)
            {
                y += 3; boxes.Add(new CardBox { Kind = "sep", R = new RectD(Pad, y, inner, 1) }); y += SepH - 3;
                if (c.Tiles.Count > 0)
                {
                    var rects = TileRects(c.Tiles, Pad, y, inner);
                    double th = 0;
                    for (int i = 0; i < c.Tiles.Count; i++)
                    {
                        var t = c.Tiles[i];
                        boxes.Add(new CardBox { Kind = "tile", R = rects[i], Caption = t.Caption, Text = t.Value, Hero = t.Hero });
                        th = Math.Max(th, rects[i].H);
                    }
                    y += th + Gap;
                }
                if (c.Effect.Length > 0) { boxes.Add(new CardBox { Kind = "effect", Text = c.Effect, Color = c.EffectColor, R = new RectD(Pad, y, inner, TileH - 8) }); y += TileH - 8 + Gap; }
                foreach (var parts in c.ExtraLines) { boxes.Add(new CardBox { Kind = "extra", Parts = parts, R = new RectD(Pad, y, inner, LineH) }); y += LineH; }
                if (c.ExtraLines.Count > 0) y += 2;
            }
            Action<List<TipGroup>> groups = list =>
            {
                foreach (var g in list)
                {
                    y += 3; boxes.Add(new CardBox { Kind = "sep", R = new RectD(Pad, y, inner, 1) }); y += SepH - 3;
                    if (g.Caption.Length > 0) { boxes.Add(new CardBox { Kind = "caption", Text = g.Caption, Color = g.CapColor.Length > 0 ? g.CapColor : TipLines.Dim, R = new RectD(Pad, y, inner, CaptionH) }); y += CaptionH; }
                    foreach (var r in g.Rows)
                    {
                        boxes.Add(new CardBox { Kind = "row", Text = r.Text, Color = r.Color, Parts = r.Parts, Tag = r.Tag, TagColor = r.TagColor, Range = r.Range, Top = r.Top, Hero = r.IsMod, R = new RectD(Pad, y, inner, LineH) });
                        y += LineH;
                    }
                }
            };
            groups(c.Mods);
            groups(c.Extras);
            Action<string, List<TipChip>> chips = (caption, list) =>
            {
                if (list.Count == 0) return;
                y += 3; boxes.Add(new CardBox { Kind = "sep", R = new RectD(Pad, y, inner, 1) }); y += SepH - 3;
                if (caption.Length > 0) { boxes.Add(new CardBox { Kind = "fitcaption", Text = caption, Color = TipLines.Dim, R = new RectD(Pad, y, inner, CaptionH) }); y += CaptionH; }
                var widths = new List<double>();
                foreach (var ch in list) widths.Add(measureW(ch.Text, 11) + ChipPad);
                foreach (var row in ChipRows(widths, ChipGap, inner))
                {
                    double x = Pad;
                    foreach (int i in row)
                    {
                        boxes.Add(new CardBox { Kind = "chip", Text = list[i].Text, Color = list[i].Color, Low = list[i].Low, R = new RectD(x, y, widths[i], ChipH) });
                        x += widths[i] + ChipGap;
                    }
                    y += ChipH + ChipGap;
                }
            };
            chips("", c.Chips);
            chips(c.FitCaption, c.FitChips);
            if (c.Foot.Count > 0)
            {
                y += 3; boxes.Add(new CardBox { Kind = "sep", R = new RectD(Pad, y, inner, 1) }); y += SepH - 3;
                foreach (var f in c.Foot) { boxes.Add(new CardBox { Kind = "foot", Text = f.Text, Color = f.Color, R = new RectD(Pad, y, inner, LineH) }); y += LineH; }
            }
            if (notes != null)
                foreach (var n in notes)
                {
                    if (n.Sep) { y += 3; boxes.Add(new CardBox { Kind = "sep", R = new RectD(Pad, y, inner, 1) }); y += SepH - 3; }
                    boxes.Add(new CardBox { Kind = "foot", Text = n.Text, Color = n.Color, Parts = n.Parts, R = new RectD(Pad, y, inner, LineH) });
                    y += LineH;
                }
            height = y + Pad;
            return boxes;
        }
    }
}
