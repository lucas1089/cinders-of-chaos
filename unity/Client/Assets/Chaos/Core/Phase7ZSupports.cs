// Phase 7, track Z: game_spellsupports. Pips on the hotbar slot of a spell with supports (one small square per socketed rune, in the rune's colour) and the supports lines of
// the spellbook details (spellsupports.lua decorateButton). Pure.
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>A socket of the selected spell as a drop target: its rect in window coordinates, and whether a rune may go in (open and empty).</summary>
    public struct SocketTarget
    {
        public float X, Y, W, H;
        public int Spell, Slot;
        public bool Free;
    }

    public static class SupportDrop
    {
        /// <summary>The free socket under a point, -1 when none (or the point is outside the view that clips the sockets: viewTop..viewBottom).</summary>
        public static int Hit(IList<SocketTarget> targets, float x, float y, float viewTop, float viewBottom)
        {
            if (y < viewTop || y > viewBottom) return -1;
            for (int i = 0; i < targets.Count; i++)
            {
                var t = targets[i];
                if (t.Free && x >= t.X && x < t.X + t.W && y >= t.Y && y < t.Y + t.H) return i;
            }
            return -1;
        }
    }

    public static class SupportPips
    {
        public const string DefaultColor = "#d6c9ae";
        public const int PipSize = 5, PipGap = 1;

        /// <summary>The colours of the pips of a spell: one per socketed rune (the server's bar entry), none for a spell without supports.</summary>
        public static List<string> Colors(SpellSupportsState s, int spellId)
        {
            var o = new List<string>();
            if (s == null || spellId <= 0) return o;
            foreach (var r in s.BarRunes(spellId))
            {
                string c = Json.Text(r, "color");
                o.Add(c.Length > 0 ? c : DefaultColor);
            }
            return o;
        }

        /// <summary>The tooltip of a hotbar slot: its own text, a blank line, then "Supports:" and one line per rune. The base text without supports stays as it is.</summary>
        public static string Tip(SpellSupportsState s, int spellId, string baseTip)
        {
            if (s == null || spellId <= 0) return baseTip;
            var lines = new List<string>();
            foreach (var r in s.BarRunes(spellId)) lines.Add("  " + Json.Text(r, "name") + ": " + Json.Text(r, "text"));
            if (lines.Count == 0) return baseTip;
            string head = string.IsNullOrEmpty(baseTip) ? "" : baseTip + "\n\n";
            return head + Loc.T("Supports") + ":\n" + string.Join("\n", lines);
        }

        /// <summary>The width of the pip strip of n pips.</summary>
        public static float Width(int n) => n <= 0 ? 0 : n * PipSize + (n - 1) * PipGap;
    }
}
