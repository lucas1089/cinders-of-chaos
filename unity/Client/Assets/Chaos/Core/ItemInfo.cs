// Item rarity (client game_itemrarity, feature 126) and rich item tooltips (client game_itemtooltip, extended opcode 242,
// server item_tooltip.lua / item_tooltip_core.lua). Pure C#.
//
// Rarity: an item of an Identity.Chaos connection carries custom attributes (Item.Attrs, keys in ItemAttr). Rarity 1 Common, 2 Uncommon,
// 3 Magic, 4 Rare, 5 Legendary, 10 Divine (an old item may carry 6 .. 9 = Legendary, 11 .. 15 = Divine). The unique flag (key 4) wins
// the frame colour. Without the attributes (Identity Extended) an item has no rarity: the main client's "[NAME]" description tag
// fallback needs item descriptions, which the 10.98 wire only gives through 0x8C look texts, so Unity does not use it.
//
// Tooltips, client -> server:  get {items = [{pos = {x, y, z}, iid (decimal string), cid (client id), n (count of a stackable)}]}
//                server -> client:  tips {items = [{pos, iid, tip} | {pos, iid, gone}]}
// pos is {0xFFFF, slot, 0} for the inventory and {0xFFFF, 0x40 + container id, slot on the page the window shows} for an open container.
// A tooltip is cached by the per-item id and version (attributes 6 and 7); an item without them is cached 30 s under its position, id and
// count. An answer is kept only when it is for the item asked (client id and count): the slots of a bag shift when an item goes in.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>Keys of the item custom attributes (server const.h ChaosItemAttrKey, client game_itemrarity ChaosItemAttr).</summary>
    public static class ItemAttr
    {
        public const ushort Rarity = 1, Level = 2, Locked = 3, Unique = 4, Sockets = 5, Id = 6, Version = 7, Appearance = 8;
    }

    public static class ItemRarity
    {
        public const string UniqueColor = "#e07b24", NoColor = "#ffffff";
        static readonly Dictionary<int, string[]> Rows = new Dictionary<int, string[]>();
        /// <summary>The rarities of today in order (an item carries one of these ids).</summary>
        public static readonly int[] Ids = { 1, 2, 3, 4, 5, 10 };

        static ItemRarity()
        {
            Add(1, "Common", "#c8c8c8"); Add(2, "Uncommon", "#5ccf5c"); Add(3, "Magic", "#4a90ff"); Add(4, "Rare", "#a35cf0");
            Add(5, "Legendary", "#ffd040"); Add(10, "Divine", "#c8e8ff");
            for (int i = 6; i <= 9; i++) Rows[i] = Rows[5];
            for (int i = 11; i <= 15; i++) Rows[i] = Rows[10];
        }

        static void Add(int id, string name, string color) { Rows[id] = new[] { name, color }; }

        /// <summary>The id of today's rarity an id stands for (6 .. 9 -> 5, 11 .. 15 -> 10); 0 for an unknown one.</summary>
        public static int Canon(int id)
        {
            if (!Rows.TryGetValue(id, out var row)) return 0;
            foreach (int c in Ids) if (Rows[c] == row) return c;
            return 0;
        }

        /// <summary>The rarity id of an item (0 = none).</summary>
        public static int Of(Item it) => it == null ? 0 : Canon((int)Math.Min(it.Attr(ItemAttr.Rarity), 1000UL));
        public static bool IsUnique(Item it) => it != null && it.Attr(ItemAttr.Unique) > 0;
        public static bool IsLocked(Item it) => it != null && it.Attr(ItemAttr.Locked) > 0;
        public static string Name(int id) => Rows.TryGetValue(id, out var r) ? r[0] : null;
        public static string Color(int id) => Rows.TryGetValue(id, out var r) ? r[1] : null;

        /// <summary>The frame colour of an item (hex): the unique colour, else the rarity colour, else null.</summary>
        public static string FrameColor(Item it)
        {
            if (it == null) return null;
            if (IsUnique(it)) return UniqueColor;
            return Color(Of(it));
        }

        /// <summary>The frame colour for a rarity id and a unique flag the server sent as data (the stash list: rarity), else null.</summary>
        public static string FrameColor(int rarityId, bool unique) => unique ? UniqueColor : Color(Canon(rarityId));
    }

    /// <summary>One line of a tooltip. Parts, when set, colour pieces of the line: text, colour, text, colour ...</summary>
    public sealed class TipLine
    {
        public string Text, Color;
        public bool Sep;
        public string[] Parts;
        public override string ToString() => Text;
    }

    /// <summary>What a tooltip says (port of client game_itemtooltip tooltiplogic.lua L.lines, without the compare view, the source lines
    /// and the card layout). Colours are hex strings.</summary>
    public static class TipLines
    {
        public const int Wrap = 44;
        public const string Text = "#d6c9ae", Dim = "#8c8070", Gold = "#e8b84a", Mod = "#9ab8ff", Chaos = "#e080d0", Element = "#ffa060",
            Gem = "#c8e8ff", Empty = "#6b6258", Power = "#ff9a3c", Bound = "#e8b84a", Quality = "#7fe0a0", Red = "#e03a1e", UniqueC = "#e07b24",
            Corrupted = "#d04040", Normal = "#e4d8c0", SetC = "#58c878", SetOn = "#7fe0a0", SetLow = "#c0805a", PassiveC = "#ffb340",
            PassiveText = "#f2e6cc", Veiled = "#b48cff", VeiledText = "#d9c8ff";
        public static readonly string[] TierColors = { "#8c8070", "#a89c88", "#c8c8c8", "#5ccf5c", "#4a90ff", "#a35cf0", "#ffd040", "#ff8a40" };
        public static readonly string[] VeilTierColors = { "#9a8cc0", "#a98cff", "#c070ff", "#ff70e0" };

        static double Num(object o, string key) => Json.Number(o, key, double.NaN);
        static bool Has(object o, string key) => Json.Get(o, key) != null;

        /// <summary>1.5 -> "1.5", 3 -> "3" (up to two decimals).</summary>
        public static string Trim(double n)
        {
            if (n == Math.Floor(n)) return ((long)n).ToString(CultureInfo.InvariantCulture);
            return n.ToString("0.##", CultureInfo.InvariantCulture);
        }

        /// <summary>12345 -> "12,345".</summary>
        public static string Int(double n)
        {
            long v = (long)Math.Floor(double.IsNaN(n) ? 0 : n);
            return v.ToString("N0", CultureInfo.InvariantCulture);
        }

        public static string FormatValue(double v, string fmt, bool signed, bool rate)
        {
            string s;
            if (fmt == "sec")
            {
                s = Trim(v) + "s";
                if (rate && v > 0 && v < 1) s += " (" + Trim(Math.Floor(10 / v + 0.5) / 10) + "/s)";
            }
            else if (fmt == "pct") s = Trim(v) + "%";
            else if (fmt == "est") s = "~" + Int(v);
            else s = Trim(v);
            if (signed && v > 0 && fmt != "sec") s = "+" + s;
            return s;
        }

        public static string BaseValue(object b, bool signed)
        {
            string fmt = Json.Text(b, "fmt");
            if (fmt == "range" && Has(b, "lo") && Has(b, "hi"))
            {
                double lo = Num(b, "lo"), hi = Num(b, "hi");
                return lo == hi ? Int(lo) : Int(lo) + "-" + Int(hi);
            }
            return FormatValue(Json.Number(b, "v"), fmt, signed, true);
        }

        /// <summary>Splits a text into lines of at most n characters at spaces.</summary>
        public static List<string> WrapText(string text, int n = Wrap)
        {
            var lines = new List<string>();
            string line = "";
            foreach (string word in (text ?? "").Split(new[] { ' ', '\t', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.Length == 0) line = word;
                else if (line.Length + 1 + word.Length <= n) line += " " + word;
                else { lines.Add(line); line = word; }
            }
            if (line.Length > 0) lines.Add(line);
            return lines;
        }

        /// <summary>Item names come lower case from the item types: the title starts with a capital.</summary>
        public static string Title(string name)
        {
            name = name ?? "";
            return name.Length == 0 ? name : char.ToUpperInvariant(name[0]) + name.Substring(1);
        }

        public static string TierColor(int tier) => tier >= 1 && tier <= TierColors.Length ? TierColors[tier - 1] : Dim;

        /// <summary>The title colour: set green, unique orange, else the rarity colour, else plain.</summary>
        public static string TitleColor(object tip)
        {
            object unique = Json.Get(tip, "unique");
            if (unique is Dictionary<string, object>) return Json.Get(unique, "set") is Dictionary<string, object> ? SetC : UniqueC;
            return ItemRarity.Color(ItemRarity.Canon((int)Json.Number(tip, "rarity"))) ?? Normal;
        }

        /// <summary>The kind line ('Legendary Wand', 'Unique Quiver', 'Set Ring'), or null; slotLine when the slot reads 'Where: What'.</summary>
        public static string KindText(object tip, out string slotLine)
        {
            var sub = new List<string>();
            object unique = Json.Get(tip, "unique");
            if (unique is Dictionary<string, object>) sub.Add(Json.Get(unique, "set") is Dictionary<string, object> ? Loc.T("Set") : Loc.T("Unique"));
            else if (Json.Text(tip, "rarityName").Length > 0) sub.Add(Loc.T(Json.Text(tip, "rarityName")));
            string slot = Json.Text(tip, "slot");
            string what = slot;
            slotLine = null;
            int colon = slot.IndexOf(": ", StringComparison.Ordinal);
            if (colon >= 0) { what = slot.Substring(colon + 2); slotLine = slot; }
            if (what.Length > 0) sub.Add(Loc.T(what));
            return sub.Count > 0 ? string.Join(" ", sub) : null;
        }

        internal static string Range(object m)
        {
            if (!Has(m, "lo") || !Has(m, "hi")) return "";
            double lo = Num(m, "lo"), hi = Num(m, "hi");
            return lo == hi ? " [" + Int(lo) + "]" : " [" + Int(lo) + "-" + Int(hi) + "]";
        }

        internal static string ChargesText(object ch)
        {
            if (!(ch is Dictionary<string, object>)) return null;
            if (Json.Truthy(ch, "unlimited")) return Loc.T("Charges: unlimited");
            if (!Has(ch, "n")) return null;
            double n = Num(ch, "n"), max = Has(ch, "max") ? Num(ch, "max") : double.NaN;
            if (!double.IsNaN(max) && max > n) return Loc.T("Charges: {0} of {1}", Int(n), Int(max));
            return Loc.T("Charges: {0}", Int(n));
        }

        internal sealed class Out
        {
            public readonly List<TipLine> Lines = new List<TipLine>();
            public void Add(string text, string color, bool sep = false, string[] parts = null)
            {
                Lines.Add(new TipLine { Text = text, Color = color ?? Text, Sep = sep, Parts = parts });
            }
        }

        /// <summary>The set block of a piece: header, active tier, pieces (worn bright), bonuses (active bright).</summary>
        internal static void SetLines(Out o, object set)
        {
            if (!(set is Dictionary<string, object>)) return;
            string name = Json.Text(set, "name", "?");
            o.Add(Loc.T("Set: {0} ({1}/{2})", name, (int)Json.Number(set, "have"), (int)Json.Number(set, "total")), SetC, true);
            if (Has(set, "tiers"))
            {
                int tier = (int)Json.Number(set, "tier");
                o.Add(Loc.T("Active tier: {0} of {1}", tier, (int)Json.Number(set, "tiers")), tier > 0 ? SetOn : Dim);
            }
            foreach (object p in Json.List(set, "pieces"))
            {
                string text = "  " + Json.Text(p, "n", "?");
                if (Json.Number(p, "h", 1) > 1) text += Loc.T(" (counts {0})", (int)Json.Number(p, "h"));
                string color = Empty;
                if (Json.Truthy(p, "eq")) color = SetOn;
                else if (Json.Truthy(p, "low")) { text += Loc.T(" (level {0})", (int)Json.Number(p, "lv")); color = SetLow; }
                o.Add(text, color);
            }
            bool first = true;
            foreach (object b in Json.List(set, "bonuses"))
            {
                string color = Json.Truthy(b, "on") ? SetOn : Dim;
                int j = 0;
                foreach (string line in WrapText("(" + (int)Json.Number(b, "n") + ") " + Json.Text(b, "t"), Wrap))
                    o.Add((j++ > 0 ? "    " : "") + line, color, first && j == 1);
                first = false;
            }
        }

        static void VeilLines(Out o, object veil)
        {
            if (!(veil is Dictionary<string, object>)) return;
            string s = Json.Text(veil, "s");
            if (s == "veiled")
            {
                o.Add(Loc.T("Veiled modifier"), Veiled, true);
                o.Add(Loc.T("  Reveal it with an Orb of Unveiling"), Dim);
                return;
            }
            if (s != "open") return;
            o.Add(Loc.T("Veiled"), Veiled, true);
            int tr = (int)Json.Number(veil, "tr", 1);
            string tag = Json.Text(veil, "tn", "V" + tr) + " ";
            string name = Json.Text(veil, "n", "?");
            string range = Range(veil);
            string tierColor = tr >= 1 && tr <= VeilTierColors.Length ? VeilTierColors[tr - 1] : Veiled;
            o.Add(tag + name + range, Veiled, false, new[] { tag, tierColor, name, Veiled, range, Dim });
            foreach (string line in WrapText(Json.Text(veil, "t"), Wrap)) o.Add("  " + line, VeiledText);
        }

        /// <summary>The lines of a tooltip. playerLevel: the character's level (a requirement above it is red).</summary>
        public static List<TipLine> Lines(object tip, int playerLevel)
        {
            var o = new Out();
            string kind = KindText(tip, out string slotLine);
            if (kind != null) o.Add(kind, TitleColor(tip));
            if (slotLine != null) o.Add(slotLine, Dim);
            if (Has(tip, "level"))
                o.Add(Loc.T("Item Level {0}", (int)Json.Number(tip, "level")) + (Has(tip, "maxTier") ? Loc.T("  (up to T{0})", (int)Json.Number(tip, "maxTier")) : ""), Dim);
            object quality = Json.Get(tip, "quality");
            if (quality is Dictionary<string, object> && Json.Number(quality, "q") > 0)
                o.Add(Loc.T("Quality +{0}%  (up to {1}%)", (int)Json.Number(quality, "q"), (int)Json.Number(quality, "cap", 20)), Quality);
            if (Json.Truthy(tip, "ruined")) o.Add(Loc.T("Ruined: no orb can change this item"), Red);
            if (Json.Truthy(tip, "corrupted")) o.Add(Loc.T("Corrupted: no orb can change this item"), Corrupted);

            bool first = true;
            foreach (object b in Json.List(tip, "base"))
            {
                bool imp = Json.Truthy(b, "imp");
                string key = Json.Text(b, "k");
                bool signed = imp || (Json.Text(b, "fmt") == "pct" && key.StartsWith("protect", StringComparison.Ordinal));
                o.Add(Json.Text(b, "l") + ": " + BaseValue(b, signed), imp ? Chaos : Text, first);
                first = false;
            }

            first = true;
            string side = null;
            object sides = Json.Get(tip, "sides");
            foreach (object m in Json.List(tip, "mods"))
            {
                string sd = Json.Text(m, "sd");
                if (sd.Length > 0 && sd != side)
                {
                    side = sd;
                    string head = sd == "p" ? Loc.T("Prefixes") : Loc.T("Suffixes");
                    if (sd == "i") head = Loc.T("Corrupted implicit");
                    else if (sides is Dictionary<string, object> && Has(sides, "max"))
                    {
                        double limit = Has(sides, sd == "p" ? "mp" : "ms") ? Num(sides, sd == "p" ? "mp" : "ms") : Num(sides, "max");
                        head = head + " " + (int)Json.Number(sides, sd == "p" ? "p" : "s") + "/" + (int)limit;
                    }
                    o.Add(head, Dim, first);
                    first = false;
                }
                string g = Json.Text(m, "g");
                string color = sd == "i" ? Corrupted : Json.Truthy(m, "pw") ? Power : g == "chaos" ? Chaos : g == "element" ? Element : Mod;
                string range = Range(m);
                string t = Json.Text(m, "t");
                if (Has(m, "tr"))
                {
                    int tr = (int)Json.Number(m, "tr");
                    string tag = "T" + tr + " ";
                    bool bound = Json.Truthy(m, "bd");
                    var parts = new List<string> { tag, TierColor(tr), t, color, range, Dim };
                    if (bound) { parts.Add(" " + Loc.T("[bound]")); parts.Add(Bound); }
                    o.Add(tag + t + range + (bound ? " " + Loc.T("[bound]") : ""), color, first, parts.ToArray());
                }
                else o.Add(t + range, color, first, range.Length > 0 ? new[] { t, color, range, Dim } : null);
                first = false;
            }

            VeilLines(o, Json.Get(tip, "veil"));

            object sockets = Json.Get(tip, "sockets");
            if (sockets is Dictionary<string, object> && Json.Number(sockets, "count") > 0)
            {
                int count = (int)Json.Number(sockets, "count"), filled = 0;
                var list = Json.List(sockets, "list");
                for (int i = 0; i < count; i++) if (i < list.Count && Json.Text(list[i], "name").Length > 0) filled++;
                o.Add(Loc.T("Sockets {0}/{1}", filled, count), Gold, true);
                for (int i = 0; i < count; i++)
                {
                    object gem = i < list.Count ? list[i] : null;
                    string name = Json.Text(gem, "name");
                    if (name.Length > 0)
                    {
                        string text = Json.Text(gem, "text");
                        string col = Json.Text(gem, "color", Gem);
                        o.Add("  " + name + (text.Length > 0 ? ": " + text : ""), col, false, new[] { "  " + name, col, text.Length > 0 ? ": " + text : "", Gem });
                    }
                    else o.Add(Loc.T("  empty socket"), Empty);
                }
            }

            object unq = Json.Get(tip, "unique");
            object set = unq is Dictionary<string, object> && Json.Get(unq, "set") is Dictionary<string, object> ? Json.Get(unq, "set") : Json.Get(tip, "set");
            SetLines(o, set);

            object req = Json.Get(tip, "req");
            if (req is Dictionary<string, object>)
            {
                bool sep = true;
                if (Has(req, "level"))
                {
                    int need = (int)Json.Number(req, "level");
                    o.Add(Loc.T("Requires level {0}", need), playerLevel < need ? Red : Dim, sep);
                    sep = false;
                }
                if (Has(req, "magic")) { o.Add(Loc.T("Requires magic level {0}", (int)Json.Number(req, "magic")), Dim, sep); sep = false; }
                if (Json.Text(req, "voc").Length > 0)
                {
                    int i = 0;
                    foreach (string line in WrapText(Loc.T("For {0}", Json.Text(req, "voc")), Wrap)) o.Add(line, Dim, sep && i++ == 0);
                }
            }

            if (Json.Text(tip, "note").Length > 0)
            {
                int i = 0;
                foreach (string line in WrapText(Json.Text(tip, "note"), Wrap)) o.Add(line, Gold, i++ == 0);
            }
            object passive = Json.Get(tip, "passive");
            bool hasPassive = passive is Dictionary<string, object> && Has(passive, "name") && Has(passive, "text");
            string desc = hasPassive ? Json.Text(passive, "flavor") : Json.Text(tip, "desc");
            if (desc.Length > 0)
            {
                int i = 0;
                foreach (string line in WrapText(desc, Wrap)) o.Add(line, Dim, i++ == 0);
            }
            if (hasPassive)
            {
                o.Add(Json.Text(passive, "name"), PassiveC, true);
                foreach (string line in WrapText(Json.Text(passive, "text"), Wrap)) o.Add(line, PassiveText);
            }
            bool locked = Json.Truthy(tip, "locked");
            if (locked) o.Add(Loc.T("Locked"), Gold, true);
            object look = Json.Get(tip, "look");
            if (look is Dictionary<string, object> && Json.Text(look, "name").Length > 0) o.Add(Loc.T("Appearance: {0}", Json.Text(look, "name")), Mod, !locked);
            if (Json.Text(tip, "store").Length > 0) o.Add(Json.Text(tip, "store"), Gold, true);
            if (Json.Text(tip, "collects").Length > 0)
                foreach (string line in WrapText(Json.Text(tip, "collects"), Wrap)) o.Add(line, Dim);
            string charges = ChargesText(Json.Get(tip, "charges"));
            if (charges != null) o.Add(charges, Text, true);
            // where it comes from (server itemfinder.lua F.brief): the first sources, the expected effort, a token price
            var src = SourceLines(Json.Get(tip, "src"));
            for (int i = 0; i < src.Count; i++) o.Add(src[i].Text, src[i].Color, i == 0);
            if (Has(tip, "weight"))
                o.Add(Loc.T("Weight {0} oz", Trim(Num(tip, "weight"))), Dim, src.Count == 0 && !locked && Json.Text(tip, "store").Length == 0);
            return o.Lines;
        }

        /// <summary>1 / p as a player reads it (1-20 exact, then 5s, 10s, 50s, 100s); 0 when p is not a chance (goals_core.lua K.oneIn).</summary>
        public static int OneIn(double p)
        {
            if (!(p > 0)) return 0;
            double n = 1 / p;
            if (n < 1.5) return 1;
            double step = n < 20 ? 1 : n < 200 ? 5 : n < 1000 ? 10 : n < 10000 ? 50 : 100;
            return (int)Math.Max(1, Math.Floor(n / step + 0.5) * step);
        }

        /// <summary>The sources block of a tooltip: src = {s = [{k, n, v}], e = {p, w, m}, t = token price, u = {n = [names], m = more}} (tooltiplogic.lua sourceLines).</summary>
        public static List<TipLine> SourceLines(object src)
        {
            var rows = new List<TipLine>();
            if (!(src is Dictionary<string, object>)) return rows;
            var parts = new List<string>();
            var seen = new HashSet<string>();
            var list = Json.List(src, "s");
            foreach (object s in list)
            {
                string n = Json.Text(s, "n");
                if (n.Length == 0 || !seen.Add(n)) continue;
                string v = Json.Get(s, "v") is double dv ? Trim(dv) : Json.Text(s, "v");
                parts.Add(v.Length > 0 ? n + " (" + v + ")" : n);
            }
            if (parts.Count > 0)
            {
                string k = Json.Text(list[0], "k");
                bool drop = k == "monster" || k == "drop";
                string text = drop ? Loc.T("Drops from: {0}", string.Join(", ", parts)) : Loc.T("Sources: {0}", string.Join(", ", parts));
                foreach (string line in WrapText(text, Wrap)) rows.Add(new TipLine { Text = line, Color = Dim });
            }
            string effort = null;
            object e = Json.Get(src, "e");
            int one = e is Dictionary<string, object> ? OneIn(Json.Number(e, "p")) : 0;
            if (one > 0)
            {
                string count = Int(one), w = Json.Text(e, "w"), m = Json.Text(e, "m");
                if (w == "legendary") effort = Loc.T("~1 in {0} legendary kills", count);
                else if (w == "boss") effort = Loc.T("~1 in {0} boss kills", count);
                else if (m.Length > 0) effort = Loc.T("~1 in {0} kills of {1}", count, m);
                else effort = Loc.T("~1 in {0} kills", count);
            }
            double price = Json.Number(src, "t");
            if (effort != null && price > 0) effort += Loc.T(", or {0} Conquest Tokens", Int(price));
            else if (price > 0) effort = Loc.T("Conquest vendor: {0} tokens", Int(price));
            if (effort != null) foreach (string line in WrapText(effort, Wrap)) rows.Add(new TipLine { Text = line, Color = Gold });
            object u = Json.Get(src, "u");
            var names = new List<string>();
            foreach (object n in Json.List(u, "n")) if (n is string ns && ns.Length > 0) names.Add(ns);
            if (names.Count > 0)
            {
                string joined = string.Join(", ", names);
                int more = (int)Math.Floor(Json.Number(u, "m"));
                if (more > 0) joined = Loc.T("{0} +{1} more", joined, more);
                foreach (string line in WrapText(Loc.T("Used in: {0}", joined), Wrap)) rows.Add(new TipLine { Text = line, Color = Dim });
            }
            return rows;
        }
    }

    /// <summary>What one tooltip request names: where the item is, its per-item id, client id and (stackables) count.</summary>
    public sealed class TipIdent
    {
        public string Key;
        public bool Plain;
        public int X, Y, Z;
        public ulong Iid;
        public int Cid, Count;   // Count 0 = not a stackable

        public string PosKey => X + "," + Y + "," + Z + "," + Iid.ToString(CultureInfo.InvariantCulture);
    }

    /// <summary>The client side of opcode 242: asks after a short hover, caches, matches the answer to the item asked.</summary>
    public sealed class ItemTips
    {
        public const byte Opcode = 242;
        public const double AskDelayMs = 60, PendingTimeoutMs = 2000, PlainTtlMs = 30000;
        public const int MaxCache = 400, Retries = 2;

        sealed class Entry { public object Tip; public double Expires; }
        sealed class Pending { public string Key; public bool Plain; public double At; public int Cid, Count; public int Tries; }

        readonly ExtOpcodes ext;
        public Func<double> Clock = () => 0;
        readonly Dictionary<string, Entry> cache = new Dictionary<string, Entry>();
        readonly List<string> order = new List<string>();
        readonly Dictionary<string, Pending> pending = new Dictionary<string, Pending>();
        string hoverKey;
        double hoverSince;
        public int Asked, Answers, Mismatches;

        public ItemTips(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        /// <summary>The request identity of an item at a tooltip position (pos.Z of a container slot is the slot on the shown page).</summary>
        public static TipIdent Describe(Item it, Pos pos)
        {
            var d = new TipIdent { X = pos.X, Y = pos.Y, Z = pos.Z, Iid = it.Attr(ItemAttr.Id), Cid = it.Id };
            bool stackable = it.Type != null && it.Type.Stackable;
            d.Count = stackable ? Math.Max(1, it.Count) : 0;
            ulong ver = it.Attr(ItemAttr.Version);
            if (d.Iid > 0) { d.Key = d.Iid.ToString(CultureInfo.InvariantCulture) + ":" + ver.ToString(CultureInfo.InvariantCulture); d.Plain = false; }
            else { d.Key = "p:" + pos.X + ":" + pos.Y + ":" + pos.Z + ":" + it.Id + ":" + Math.Max(1, it.Count); d.Plain = true; }
            return d;
        }

        /// <summary>Only the inventory and open containers are asked about (the server checks again).</summary>
        public static bool Askable(Pos p) => p.X == 0xFFFF && ((p.Y >= 1 && p.Y <= 16) || (p.Y >= 0x40 && p.Y < 0x50));

        /// <summary>The cached tooltip (a JSON object) of an item, or null. Asks the server when the pointer has rested on the item
        /// for AskDelayMs and no request for it is open.</summary>
        public object Lookup(TipIdent d, double now)
        {
            if (d == null || !Askable(new Pos(d.X, d.Y, d.Z))) return null;
            if (cache.TryGetValue(d.Key, out var e))
            {
                if (e.Expires > 0 && now > e.Expires) Drop(d.Key);
                else return e.Tip;
            }
            if (hoverKey != d.Key) { hoverKey = d.Key; hoverSince = now; }
            if (now - hoverSince < AskDelayMs) return null;
            pending.TryGetValue(d.PosKey, out var p);
            if (p != null && p.Key == d.Key && now - p.At <= PendingTimeoutMs) return null;
            Ask(d, now, p != null && p.Key == d.Key ? p.Tries : 0);
            return null;
        }

        /// <summary>The cached tooltip of another item (a worn one for the Ctrl compare): asked at once, without the hover delay and without
        /// touching the hovered key. waiting is true while an answer is on its way.</summary>
        public object Quick(TipIdent d, double now, out bool waiting)
        {
            waiting = false;
            if (d == null || !Askable(new Pos(d.X, d.Y, d.Z))) return null;
            if (cache.TryGetValue(d.Key, out var e))
            {
                if (e.Expires > 0 && now > e.Expires) Drop(d.Key);
                else return e.Tip;
            }
            pending.TryGetValue(d.PosKey, out var p);
            waiting = true;
            if (p != null && p.Key == d.Key && now - p.At <= PendingTimeoutMs) return null;
            Ask(d, now, p != null && p.Key == d.Key ? p.Tries : 0);
            return null;
        }

        /// <summary>The pointer left every item: the next hover waits the delay again.</summary>
        public void HoverEnded() { hoverKey = null; }

        void Ask(TipIdent d, double now, int tries)
        {
            var pos = new Dictionary<string, object> { { "x", d.X }, { "y", d.Y }, { "z", d.Z } };
            var item = new Dictionary<string, object> { { "pos", pos }, { "iid", d.Iid.ToString(CultureInfo.InvariantCulture) }, { "cid", d.Cid } };
            if (d.Count > 0) item["n"] = d.Count;
            pending[d.PosKey] = new Pending { Key = d.Key, Plain = d.Plain, At = now, Cid = d.Cid, Count = d.Count, Tries = tries };
            Asked++;
            ext.Send(Opcode, "get", new Dictionary<string, object> { { "items", new List<object> { item } } });
        }

        void Drop(string key)
        {
            cache.Remove(key);
            order.Remove(key);
        }

        void Put(string key, object tip, bool plain, double now)
        {
            if (!cache.ContainsKey(key)) order.Add(key);
            cache[key] = new Entry { Tip = tip, Expires = plain ? now + PlainTtlMs : 0 };
            while (order.Count > MaxCache) { cache.Remove(order[0]); order.RemoveAt(0); }
        }

        /// <summary>An answer is kept only for the item asked for: client id and (stackables) count must agree.</summary>
        public static bool Matches(int cid, int count, object tip)
        {
            if (cid > 0 && (int)Json.Number(tip, "id") != cid) return false;
            if (count > 0 && (int)Json.Number(tip, "count", 1) != count) return false;
            return true;
        }

        void OnMessage(ExtMessage m)
        {
            if (m.Action != "tips") return;
            double now = Clock();
            foreach (object row in Json.List(m.Data, "items"))
            {
                object pos = Json.Get(row, "pos");
                object iv = Json.Get(row, "iid");
                string iid = iv is string ivs ? ivs : iv is double ivd ? ivd.ToString("0", CultureInfo.InvariantCulture) : "0";
                string pk = (int)Json.Number(pos, "x") + "," + (int)Json.Number(pos, "y") + "," + (int)Json.Number(pos, "z") + "," + iid;
                if (!pending.TryGetValue(pk, out var p)) continue;
                pending.Remove(pk);
                object tip = Json.Get(row, "tip");
                if (!(tip is Dictionary<string, object>)) continue;
                Answers++;
                if (Matches(p.Cid, p.Count, tip)) Put(p.Key, tip, p.Plain, now);
                else
                {
                    Mismatches++;
                    // asked again by the hover (a short wait, at most Retries times): the slots shifted under the pointer
                    if (p.Tries < Retries) pending[pk] = new Pending { Key = p.Key, Plain = p.Plain, At = now - PendingTimeoutMs + 300, Cid = p.Cid, Count = p.Count, Tries = p.Tries + 1 };
                }
            }
        }

        /// <summary>The equipment changed: a set piece's block (pieces worn, bonuses) may be stale, so every cached set tooltip goes.</summary>
        public int DropSetTips()
        {
            var gone = new List<string>();
            foreach (var kv in cache)
                if (Json.Get(kv.Value.Tip, "set") != null || Json.Get(Json.Get(kv.Value.Tip, "unique"), "set") != null) gone.Add(kv.Key);
            foreach (string k in gone) Drop(k);
            return gone.Count;
        }

        public void Reset() { cache.Clear(); order.Clear(); pending.Clear(); hoverKey = null; }
        public int CacheCount => cache.Count;
    }
}
