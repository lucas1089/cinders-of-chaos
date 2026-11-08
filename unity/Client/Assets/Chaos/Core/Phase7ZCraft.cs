// Phase 7, track Z: game_crafting (the gem guide table, the Codex link of a modifier) and game_itemfinder (the Codex button). Pure.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    public sealed class GemGuideGroup { public string Label = "", Text = "", Cap = ""; }

    public sealed class GemGuideRow
    {
        public string Name = "", Color = "#d6c9ae";
        public int Look;
        public readonly List<GemGuideGroup> Groups = new List<GemGuideGroup>();
    }

    /// <summary>The Gems page of the crafting guide (craftguideview.lua gemBasics / gemRows) from the server's gemguide message (ChaosGems.guide()): numbers only, the client
    /// writes the texts.</summary>
    public static class GemGuide
    {
        /// <summary>12345 -> "12,345".</summary>
        public static string Number(double n) => ((long)Math.Floor(n)).ToString("N0", CultureInfo.InvariantCulture);

        static string Plain(double v) => v.ToString("0.##", CultureInfo.InvariantCulture);

        static string Series(object values, string suffix = "")
        {
            var parts = new List<string>();
            foreach (var v in CF.Raw(values)) parts.Add(Plain(Convert.ToDouble(v, CultureInfo.InvariantCulture)));
            return string.Join(" / ", parts) + suffix;
        }

        public static string EffectText(object def, object values, object values2)
        {
            string label = CF.T(def, "label");
            label = label.Length > 0 ? Loc.T(label) : "?";
            string fmt = CF.T(def, "fmt");
            if (fmt == "flat") return label + " +" + Series(values);
            if (fmt == "pair")
            {
                string l2 = CF.T(def, "label2");
                return label + " +" + Series(values, "%") + ", " + (l2.Length > 0 ? Loc.T(l2) : "?") + " +" + Series(values2, "%");
            }
            return label + " +" + Series(values, "%");
        }

        public static string CapText(object def)
        {
            if (CF.G(def, "cap") == null) return "";
            return Plain(CF.N(def, "cap")) + (CF.T(def, "fmt") == "flat" ? "" : "%");
        }

        /// <summary>The basics paragraphs: (heading, text). Empty before the gemguide message came.</summary>
        public static List<KeyValuePair<string, string>> Basics(object guide)
        {
            var costs = new List<string>();
            foreach (var c in CF.Raw(CF.G(guide, "removeCost"))) costs.Add(Number(Convert.ToDouble(c, CultureInfo.InvariantCulture)));
            var tiers = new List<string>();
            foreach (var t in CF.Raw(CF.G(guide, "tiers"))) tiers.Add(CF.Str(t));
            string orb = CF.T(guide, "socketOrb");
            if (orb.Length == 0) orb = "Orb of Sockets";
            var o = new List<KeyValuePair<string, string>>();
            void Add(string h, string t) => o.Add(new KeyValuePair<string, string>(Loc.T(h), t));
            Add("What a gem does", Loc.T("A gem sits in a socket of your gear and gives one bonus. The same gem gives a different bonus in a weapon, in armour (helmet, armour, legs, boots, shield) and in jewellery (amulet, ring): see the table below."));
            Add("Where gems come from", Loc.T("Monsters drop them, stronger monsters more often; higher monster levels drop better qualities. Bounties, rifts and bosses give them too, and the Candlemarks shop sells some."));
            Add("Putting a gem in", Loc.T("Use the gem, then click the item. The item needs an empty socket. An {0} rolls a new number of sockets; better rarities can hold more.", orb));
            Add("Better gems", Loc.T("Three gems of the same kind and quality become one of the next quality: use the stack, then click the same stack. Qualities: {0}.", string.Join(", ", tiers)));
            Add("Taking a gem out", Loc.T("On the crafting bench, under the bonuses of the item: Remove gives the gem back for gold ({0} by quality), Shatter is free and destroys it.", string.Join(" / ", costs)));
            Add("Limits", Loc.T("Each bonus has a total limit from all your gems together, shown after it in the table."));
            return o;
        }

        /// <summary>The gem table: one row per gem kind with the bonus per slot group.</summary>
        public static List<GemGuideRow> Rows(object guide)
        {
            var rows = new List<GemGuideRow>();
            var effects = CF.G(guide, "effects");
            foreach (var t in CF.Rows(CF.G(guide, "types")))
            {
                var looks = CF.Raw(CF.G(t, "look"));
                var row = new GemGuideRow { Name = CF.T(t, "name", "?"), Color = CF.T(t, "color", "#d6c9ae"), Look = looks.Count > 0 ? (int)Convert.ToDouble(looks[looks.Count - 1], CultureInfo.InvariantCulture) : 0 };
                foreach (string g in new[] { "weapon", "armour", "jewel" })
                {
                    var e = CF.G(t, g);
                    if (!(e is Dictionary<string, object>)) continue;
                    var def = CF.G(effects, CF.T(e, "effect"));
                    string cap = CapText(def);
                    string label = g == "weapon" ? Loc.T("Weapon") : g == "armour" ? Loc.T("Armour") : Loc.T("Jewellery");
                    row.Groups.Add(new GemGuideGroup { Label = label, Text = EffectText(def, CF.G(e, "values"), CF.G(e, "values2")), Cap = cap });
                }
                rows.Add(row);
            }
            return rows;
        }

        /// <summary>The line of a group in the table: "Weapon: Fire damage +2 / 4 / 6%  (limit 30%)".</summary>
        public static string GroupLine(GemGuideGroup g) => g.Label + ": " + g.Text + (g.Cap.Length > 0 ? "  " + Loc.T("(limit {0})", g.Cap) : "");
    }

    /// <summary>The Codex links: a server item id to the entry that lists it (itemfinderlogic.lua codexIndex, the first entry wins), and a modifier row of the crafting bench
    /// to its page (CodexView.IdForMod).</summary>
    public static class CodexLinks
    {
        public static Dictionary<int, string> ItemIndex(CodexData d)
        {
            var map = new Dictionary<int, string>();
            if (d == null) return map;
            foreach (var tab in d.Tabs)
                foreach (var e in tab.Entries)
                    foreach (int id in e.Items) if (!map.ContainsKey(id)) map[id] = e.Id;
            return map;
        }

        public static string ForItem(CodexData d, int serverId)
        {
            if (serverId <= 0) return null;
            return ItemIndex(d).TryGetValue(serverId, out string id) ? id : null;
        }

        /// <summary>The tooltip line a modifier row gets when the Codex has its page, null when not.</summary>
        public static string ModTip(CodexData d, string key, string group) => CodexView.IdForMod(key, group, d) != null ? Loc.T("Right-click: its page in the Codex.") : null;
    }
}
