// Phase 7, track Z: game_unlocks. The outfit window lists what the character owns (the server's stock list) and, after it, the wardrobe catalogue's entries it does not
// have as grey rows with how to get them (unlocks_core.lua U.display). Pure.
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>One row of an outfit window list: owned (from the server's stock list) or locked (from the wardrobe catalogue, with how to get it).</summary>
    public sealed class WardrobeRow
    {
        public int Id;
        public string Name = "", How;
        public bool Locked;

        /// <summary>The tooltip: why a row is grey and how to get it; an owned row shows its source.</summary>
        public string Tip
        {
            get
            {
                if (!Locked) return string.IsNullOrEmpty(How) ? null : Loc.T("Unlocked.") + "\n" + Loc.T(How);
                return string.IsNullOrEmpty(How) ? Loc.T("Not unlocked yet.") : Loc.T("Not unlocked yet.") + "\n" + Loc.T("How to get it: {0}", Loc.T(How));
            }
        }
    }

    /// <summary>game_unlocks U.display: the stock list plus the catalogue's entries the character does not have, as locked rows after them. Shaders are keyed by
    /// name (Id 0), the other kinds by look. onlyMine drops the locked rows ("Only what I own").</summary>
    public static class WardrobeView
    {
        public static List<WardrobeRow> Display(string kind, IEnumerable<KeyValuePair<int, string>> stock, IList<WardrobeEntry> catalogue, bool onlyMine)
        {
            bool shader = kind == "shader";
            var o = new List<WardrobeRow>();
            var have = new HashSet<string>();
            var source = new Dictionary<string, string>();
            if (catalogue != null) foreach (var c in catalogue) source[Key(shader, c.Look, c.Name)] = c.Source;
            if (stock != null)
                foreach (var e in stock)
                {
                    string k = Key(shader, e.Key, e.Value);
                    have.Add(k);
                    source.TryGetValue(k, out string how);
                    o.Add(new WardrobeRow { Id = e.Key, Name = e.Value, How = how });
                }
            if (onlyMine || catalogue == null) return o;
            foreach (var c in catalogue)
            {
                string k = Key(shader, c.Look, c.Name);
                if (k.Length == 0 || k == "0" || have.Contains(k)) continue;
                have.Add(k);
                o.Add(new WardrobeRow { Id = shader ? 0 : c.Look, Name = c.Name, How = c.Source, Locked = true });
            }
            return o;
        }

        static string Key(bool shader, int look, string name) => shader ? (name ?? "") : look.ToString(CultureInfo.InvariantCulture);

        /// <summary>Owned and all rows of a list (the "have / all" count).</summary>
        public static void Count(IList<WardrobeRow> rows, out int have, out int all)
        {
            have = all = 0;
            foreach (var r in rows) { all++; if (!r.Locked) have++; }
        }

        /// <summary>The key of the saved "Only what I own" box of a kind.</summary>
        public static string PrefsKey(string kind) => "chaos.outfit.onlymine." + kind;
    }
}
