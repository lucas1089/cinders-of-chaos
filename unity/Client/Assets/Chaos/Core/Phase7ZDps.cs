// Phase 7, track Z: game_dpsmeter. Source icons of the bars (dpsmath.lua iconSpec), the panel position kept inside the screen (clampPosition) and the resize by the corner. Pure.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>What a bar's icon is: a spell (by its words), an item (a rune, by client id), or a picture of the main client ("buff", "own") that Unity draws as a coloured glyph.</summary>
    public sealed class DpsIconSpec
    {
        public string Kind = "own";   // spell | item | buff | own
        public string Words = "", Key = "", Glyph = "?";
        public int ItemId;
    }

    public static class DpsIcons
    {
        public static readonly HashSet<string> Own = new HashSet<string>
        {
            "sword", "axe", "club", "fist", "distance", "wand", "dot", "other", "supports", "keystone", "thorns", "power", "elements", "summon", "potion", "monster", "player", "env",
        };
        public static readonly HashSet<string> Buffs = new HashSet<string> { "bleeding", "burning", "poison", "energy", "freezing", "dazzled", "cursed", "drowning", "regen" };

        static readonly Dictionary<string, string> Glyphs = new Dictionary<string, string>
        {
            { "sword", "S" }, { "axe", "A" }, { "club", "C" }, { "fist", "F" }, { "distance", "D" }, { "wand", "W" }, { "dot", "~" }, { "other", "?" }, { "supports", "+" },
            { "keystone", "K" }, { "thorns", "T" }, { "power", "P" }, { "elements", "E" }, { "summon", "Z" }, { "potion", "H" }, { "monster", "M" }, { "player", "U" }, { "env", "V" },
            { "bleeding", "B" }, { "burning", "F" }, { "poison", "P" }, { "energy", "E" }, { "freezing", "I" }, { "dazzled", "D" }, { "cursed", "C" }, { "drowning", "W" }, { "regen", "R" },
        };

        /// <summary>The icon of a row by its kind letter and icon value: a spell kind with words, a rune kind with an item id, a buff name, one of our own names; else by kind.</summary>
        public static DpsIconSpec Spec(string kind, object icon)
        {
            string text = icon as string;
            double num = icon is double d ? d : 0;
            if (kind == "s" && !string.IsNullOrEmpty(text)) return new DpsIconSpec { Kind = "spell", Words = text, Glyph = "W" };
            if (kind == "r" && num > 0) return new DpsIconSpec { Kind = "item", ItemId = (int)num, Glyph = "R" };
            if (text != null && Buffs.Contains(text)) return new DpsIconSpec { Kind = "buff", Key = text, Glyph = Glyphs[text] };
            if (text != null && Own.Contains(text)) return new DpsIconSpec { Kind = "own", Key = text, Glyph = Glyphs[text] };
            switch (kind)
            {
                case "c": return new DpsIconSpec { Kind = "own", Key = "monster", Glyph = "M" };
                case "u": return new DpsIconSpec { Kind = "own", Key = "player", Glyph = "U" };
                case "m": return new DpsIconSpec { Kind = "own", Key = "summon", Glyph = "Z" };
                case "d": return new DpsIconSpec { Kind = "own", Key = "dot", Glyph = "~" };
            }
            return new DpsIconSpec { Kind = "own", Key = "other", Glyph = "?" };
        }
    }

    /// <summary>The meter panel: a saved position that keeps at least `keep` pixels on the screen, and a size by the corner handle within the limits of DpsMath.</summary>
    public static class DpsPanel
    {
        static double Clamp(double v, double lo, double hi) => v < lo ? lo : v > hi ? hi : v;

        /// <summary>A position that keeps a panel of w x h inside a screen of pw x ph.</summary>
        public static void ClampPosition(ref float x, ref float y, float w, float h, float pw, float ph, float keep = 24)
        {
            x = (float)Clamp(x, keep - w, Math.Max(keep - w, pw - keep));
            y = (float)Clamp(y, 0, Math.Max(0, ph - Math.Min(h, keep)));
        }

        /// <summary>The size after dragging the corner handle by (dx, dy) from the size at the start of the drag.</summary>
        public static void Resize(int startW, int startH, float dx, float dy, out int w, out int h)
        {
            w = (int)Math.Round(startW + dx);
            h = (int)Math.Round(startH + dy);
            DpsMath.ClampSize(ref w, ref h);
        }
    }
}
